# get latest 22.04 ubuntu Canonical AMI image
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# create an instance
resource "aws_instance" "wordpress" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.deployer.key_name
  user_data     = data.template_file.wordpress_user_data.rendered
  tags          = local.tags
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.wordpress.id]
  associate_public_ip_address = true

   lifecycle {
    ignore_changes = [
      # Ignore changes to tags, e.g. because a management agent
      # updates these based on some ruleset managed elsewhere.
      ami,
    ]
  }
}

# create security group for aws access
resource "aws_security_group" "wordpress" {
  vpc_id = aws_vpc.main.id
  name = "allow instance connection"

  ingress {
    description      = "HTTP from Everywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]  
  }
  
  ingress {
    description      = "ssh from Everywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]  
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

output "id" {
  value = aws_instance.wordpress.arn
}

output "ip" {
  description = "Instance ip, use http://<ip> to connect to wordpress and ssh ubuntuo@<ip> for ssh"
  value = aws_instance.wordpress.public_ip 
}