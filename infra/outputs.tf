output "team_name" {
  description = "team name"
  value = var.team_name
}

output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "프라이빗 서브넷 ID 리스트"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "퍼블릭 서브넷 ID 리스트"
  value       = module.vpc.public_subnets
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 API 서버 URL"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS 클러스터 인증서 데이터"
  value       = module.eks.cluster_certificate_authority_data
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "EKS 노드 그룹 시큐리티 그룹 ID"
  value       = module.eks.node_security_group_id
}

output "ssh_key_name" {
  description = "SSH 키 페어 이름"
  value       = aws_key_pair.main.key_name
}

output "bastion_security_group_id" {
  description = "배스천 호스트 시큐리티 그룹 ID"
  value       = aws_security_group.bastion.id
}

output "access_bestion_host" {
  description = "베스천호스트 접속"
  value = "ssh -i ${local_file.ssh_private_key.filename} ubuntu@${aws_instance.bastion.public_ip}"
}

output "rds_security_group_id" {
  description = "RDS 시큐리티 그룹 ID"
  value       = aws_security_group.rds.id
}

output "rds_endpoint" {
  description = "RDS 엔드포인트 (호스트명)"
  value       = aws_db_instance.postgresql.endpoint
}

output "efs_file_system_id" {
  description = "EFS 파일 시스템 ID"
  value       = aws_efs_file_system.main.id
}

output "efs_security_group_id" {
  description = "EFS 관련 시큐리티 그룹 ID"
  value       = aws_security_group.efs.id
}

output "s3_bucket_name" {
  description = "S3 버킷 이름"
  value       = aws_s3_bucket.main.bucket
}

