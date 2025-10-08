
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = local.tags
  
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "main" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1d"
  map_public_ip_on_launch = true
  tags = local.tags
}

resource "aws_subnet" "second" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1e"
  map_public_ip_on_launch = true
  tags = local.tags
}

resource "aws_internet_gateway" "igw" {
    vpc_id = "${aws_vpc.main.id}"
    tags = local.tags
}

## create routing table for external access
resource "aws_route_table" "crt" {
    vpc_id = "${aws_vpc.main.id}"
    
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.igw.id}" 
    }
    
    tags = local.tags
}

# associate routing with our subnets
resource "aws_route_table_association" "public_subnet_1"{
    subnet_id = "${aws_subnet.main.id}"
    route_table_id = "${aws_route_table.crt.id}"
}

resource "aws_route_table_association" "public_subnet_2"{
    subnet_id = "${aws_subnet.second.id}"
    route_table_id = "${aws_route_table.crt.id}"
}

# add rds database as module
module "database" {
  source  = "terraform-aws-modules/rds/aws"
  version = ">= 5.6.0, < 6.0.0"

  identifier            = "codio-database"
  engine                = "mysql"
  allocated_storage     = 5
  instance_class        = "db.t3.micro"
  db_name               = local.database
  username              = local.user
  port                  = "3306"
  major_engine_version  = "8.0"
  family                = "mysql8.0"
  
  create_db_subnet_group = true
  subnet_ids             = [aws_subnet.main.id, aws_subnet.second.id]
  vpc_security_group_ids = [aws_security_group.database.id]

  apply_immediately   = true
  skip_final_snapshot = true
  deletion_protection = false
  tags = local.tags
}


# create security group for database access
resource "aws_security_group" "database" {
  vpc_id = aws_vpc.main.id
  name = "allow database connection"
  ingress {
    description      = "Mysql from VPC"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    cidr_blocks      = [aws_subnet.main.cidr_block, aws_subnet.second.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.tags
}

# upload terraform key pair for instance provision
resource "aws_key_pair" "deployer" {
  key_name   = "codio-deployer-key"
  public_key = "${file("/home/codio/.ssh/id_rsa.pub")}"
}

# Get user_data for instance provision
data "template_file" "wordpress_user_data" {
    template = "${file("${path.module}/files/install_wordpress.sh")}"

    vars = {
        db_user     = local.user
        db_password = module.database.db_instance_password
        db_endpoint = module.database.db_instance_address
        db_name     = local.database
    }
}