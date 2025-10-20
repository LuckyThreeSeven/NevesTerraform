variable "team_name" {
  description = "team_name"
  type = string
  default = "default_team"
}

variable "aws_region" {
  description = "배포할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_access_key" {
  description   = "aws access key"
  type          = string
  nullable      = false
  sensitive     = true
}

variable "aws_secret_key" {
  description   = "aws secret key"
  type          = string
  nullable      = false
  sensitive     = true
}

variable "db_username" {
  description = "RDS 데이터베이스 마스터 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS 데이터베이스 마스터 사용자 비밀번호"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "RDS 데이터베이스 이름"
  type        = string
  sensitive   = true
}
