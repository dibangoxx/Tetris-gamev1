# Assume Role Policy for EKS
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# EKS IAM Role
resource "aws_iam_role" "eks-role" {
  name               = "eks-cluster-cloud"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Attach EKS Cluster Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "eks-role-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-role.name
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get public subnets for cluster
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Iterate through each subnet to retrieve details
data "aws_subnet" "subnet_details" {
  count = length(data.aws_subnets.public.ids)
  id    = data.aws_subnets.public.ids[count.index]
}

# EKS Cluster Provision
resource "aws_eks_cluster" "dev" {
  name     = "EKS_CLOUD"
  role_arn = aws_iam_role.eks-role.arn

  vpc_config {
    subnet_ids = [
      for idx, subnet_id in data.aws_subnets.public.ids : subnet_id
      if data.aws_subnet.subnet_details[idx].availability_zone != "us-east-1e"
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-role-AmazonEKSClusterPolicy,
  ]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks1" {
  name = "eks-node-group-cloud"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

# Attach policies to the Node Group IAM Role
resource "aws_iam_role_policy_attachment" "eks-role-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks1.name
}

resource "aws_iam_role_policy_attachment" "eks-role-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks1.name
}

resource "aws_iam_role_policy_attachment" "eks-role-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks1.name
}

# Create EKS Node Group
resource "aws_eks_node_group" "node1" {
  cluster_name    = aws_eks_cluster.dev.name
  node_group_name = "Node-cloud-1"
  node_role_arn   = aws_iam_role.eks1.arn

  # Use the same filtered subnets
  subnet_ids = [
    for idx, subnet_id in data.aws_subnets.public.ids : subnet_id
    if data.aws_subnet.subnet_details[idx].availability_zone != "us-east-1e"
  ]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  instance_types = ["t3.micro"]

  depends_on = [
    aws_iam_role_policy_attachment.eks-role-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-role-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-role-AmazonEC2ContainerRegistryReadOnly,
  ]
}
