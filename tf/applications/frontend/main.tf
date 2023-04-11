terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "cloudflare" {
  api_token = var.cf_token
}

provider "aws" {
  region = var.region
}
resource "null_resource" "build-docker" {
  provisioner "local-exec" {
    command = "./shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}"

    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    command = templatefile("./shell-scripts/build-push-registry.sh", {
      "REGISTRY_URL" = var.registry_url
      "ENV"          = "staging"
      "PATH"         = "../../../../pipe-timer-front"
      "FRONT_URL"    = "pipetimer.com"
    })
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }
}

# EC2 Essentials
data "http" "ip" {
  url = "https://ifconfig.me/ip"
}

data "aws_ami" "ubuntu" {
  filter {
    name   = "image-id"
    values = ["ami-0e735aba742568824"] # AMI ID 지정
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_security_group" "sg_pipe_timer_frontend" {
  name = "sg_pipe_timer_frontend"

  # SSH access from the VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.ip.response_body}/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

data "template_file" "user_data" {
  template = file("${path.module}/../../scripts/add-ssh-web-app.yaml")
}

resource "aws_instance" "pipe-timer-frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.sg_pipe_timer_frontend.id]
  associate_public_ip_address = true
  user_data                   = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 15
    volume_type = "gp2"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("./frontend-priv.pem")
    host        = aws_instance.pipe-timer-frontend.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.cicd_path}",
      "chmod 755 ${var.cicd_path}",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/shell-scripts"
    destination = var.cicd_path
  }

  provisioner "file" {
    source      = "${path.module}/../../../certs"
    destination = var.cicd_path
  }


  provisioner "file" {
    source      = "${path.module}/../../../../pipe-timer-front/env"
    destination = "${var.cicd_path}/env"
  }

  provisioner "file" {
    source      = "${path.module}/../../../../pipe-timer-front/public"
    destination = "${var.cicd_path}/public"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.cicd_path}/shell-scripts/install-docker.sh",
      "${var.cicd_path}/shell-scripts/install-docker.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.cicd_path}/shell-scripts/login-docker-registry.sh",
      "${var.cicd_path}/shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "docker pull ${var.registry_url}/pipe-timer-frontend:staging",
      "docker run -itd -e NODE_ENV=staging -e NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx --env-file ${var.cicd_path}/env/.staging.env -p 443:443 -p 80:80 -v ${var.cicd_path}/certs:/etc/nginx/certs/:ro -v ${var.cicd_path}/public:/public:ro --name frontend ${var.registry_url}/pipe-timer-frontend:staging",
      "docker ps -a",
    ]
  }

  tags = {
    Name = "pipe-timer-frontend"
  }
}

# Add frontend record to DNS
resource "cloudflare_record" "pipetimer_com" {
  zone_id = var.cf_zone_id
  name    = "*.pipetimer.com"
  value   = aws_instance.pipe-timer-frontend.public_ip
  type    = "A"
  proxied = true
}


