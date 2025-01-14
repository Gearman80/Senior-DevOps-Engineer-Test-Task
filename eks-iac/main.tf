provider "aws" {
    region = var.region
}


resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block             = var.private_subnets[count.index]
  availability_zone      = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-private-subnet-${count.index}"

  }
}

resource "aws_key_pair" "eks-nodes-key" {
  key_name   = var.keypair_name              # Name of the key pair
  public_key = file("~/.ssh/id_rsa.pub")     # Path to your public key file
}

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block             = var.public_subnets[count.index]
  availability_zone      = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-${count.index}"
  }
}

#Internet gateway
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.eks_vpc.id
  tags = {
    "Name"        = "eks-igw"
  }
}

# Elastic-IP (eip) for NAT
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public.*.id, 0)
  tags = {
    Name        = "eks-nat-gateway"
  }
}
# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id =  aws_vpc.eks_vpc.id
  tags = {
    Name        = "eks-private-route-table"
  }
}

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name        = "eks-public-route-table"
  }
}
# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

# Route for NAT Gateway
resource "aws_route" "private_internet_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.nat.id
}

# Route table associations for both Public subnet
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Adjust to restrict access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes_sg" {
  name        = "eks-nodes-sg"
  description = "Security group for EKS nodes"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
    description = "Allow traffic on port 10250 for node-to-node communication"
  }

  ingress {
    from_port   = 10255
    to_port     = 10255
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
    description = "Allow traffic on port 10255 for node-to-node communication"
  }

    ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
    description = "Allow traffic on port 443 for communication with the EKS API server"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-nodes-sg"
  }
}

resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
  

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = var.max_capacity
    min_size     = var.min_capacity
  }

  instance_types = [var.instance_type]

  launch_template {
    id      = aws_launch_template.eks_node_template.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "eks_node_template" {
  name_prefix   = "eks-node-template-"
  key_name      = aws_key_pair.eks-nodes-key.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups            = [aws_security_group.eks_nodes_sg.id]
  }
}


resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "eks-cluster-role"
  }
}

resource "aws_iam_role_policy" "eks_cluster_role_policy" {
  name = "eks-cluster-role-policy"
  role = aws_iam_role.eks_cluster_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeInstances",
          "elasticloadbalancing:DescribeLoadBalancers",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_role.name
}


output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
}

output "node_security_group_id" {
  value = aws_eks_node_group.eks_nodes.resources
}