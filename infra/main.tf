# ------------------------------------------------------------------------------
# 데이터 소스
# ------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# SSH 키 페어
# ------------------------------------------------------------------------------
resource "tls_private_key" "aws_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.team_name}-key"
  public_key = tls_private_key.aws_ssh_key.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.aws_ssh_key.private_key_pem
  filename        = pathexpand("~/.ssh/${var.team_name}.pem")
  file_permission = "0400"
}

# ------------------------------------------------------------------------------
# 모듈: VPC
# ------------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.4"

  name = "${var.team_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_dns_hostnames = true
  single_nat_gateway = true

  tags = { "kubernetes.io/cluster/${var.team_name}-cluster" = "shared" }
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

}

# ------------------------------------------------------------------------------
# 모듈: EKS
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks" {
  name   = "${var.team_name}-eks-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks  = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name    = "${var.team_name}-cluster"
  kubernetes_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    main = {
      name           = "${var.team_name}-node-group"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3
      vpc_security_group_ids = [aws_security_group.eks.id]
    }
  }
}

# ------------------------------------------------------------------------------
# Bastion Host
# ------------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name   = "${var.team_name}-bastion-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "bastion_role" {
  name = "${var.team_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.team_name}-bastion-role"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_policy" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.team_name}-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_instance" "bastion" {
  ami           = "ami-00e73adb2e2c80366"
  instance_type = "t3.micro"
  subnet_id     = module.vpc.public_subnets[0]
  key_name      = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.bastion_profile.name

  tags = {
    Name = "${var.team_name}-bastion-host"
  }
}

# ------------------------------------------------------------------------------
# RDS
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${var.team_name}-db-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "${var.team_name}-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id, aws_security_group.bastion.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgresql" {
  identifier           = "${var.team_name}-db"
  allocated_storage    = 20
  storage_type         = "gp3"
  engine               = "postgres"
  engine_version       = "17.4"
  instance_class       = "db.t4g.micro"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot  = true
  publicly_accessible  = false
}

# ------------------------------------------------------------------------------
# EFS
# ------------------------------------------------------------------------------
resource "aws_security_group" "efs" {
  name   = "${var.team_name}-efs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "main" {
  creation_token = "${var.team_name}-efs"
  tags = {
    Name      = "${var.team_name}-efs"
  }
}

resource "aws_efs_mount_target" "private" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}
