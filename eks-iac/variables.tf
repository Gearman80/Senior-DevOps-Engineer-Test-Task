variable "region" {
  default = "us-west-2"
  type = string
  description = "AWS region to use for EKS"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "azs" {
  default = ["us-west-1a", "us-west-1b", "us-west-1c"]
}

variable "private_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "cluster_name" {
  default = "my-eks-test-cluster"
}

variable "cluster_version" {
  default = "1.31"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "desired_capacity" {
  default = 2
}

variable "max_capacity" {
  default = 3
}

variable "min_capacity" {
  default = 1
}

variable "keypair_name" {
  default = "eks-interview-key"
}