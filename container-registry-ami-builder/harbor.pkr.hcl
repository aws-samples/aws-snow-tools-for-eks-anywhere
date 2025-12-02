packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

variables {
  region        = "us-west-2"
  instance_type = "t2.large"
  subnet_id     = ""
  volume_size   = 30
  source_ami    = ""
  ami_name      = "ami-snow-harbor"
  harbor_version= "v2.14.1"
}

source "amazon-ebs" "harbor-al2023" {
  ami_name      = var.ami_name
  source_ami    = var.source_ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  region        = var.region
  ssh_username  = "ec2-user"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_size
    delete_on_termination = true
  }
}

build {
  sources = [
    "source.amazon-ebs.harbor-al2023"
  ]

  provisioner "file" {
    source      = "./images"
    destination = "/tmp/images"
  }

  provisioner "file" {
    source      = "./harbor-configuration.sh"
    destination = "/tmp/harbor-configuration.sh"
  }

  provisioner "file" {
    source      = "./images.txt"
    destination = "/tmp/images.txt"
  }

  provisioner "shell" {
    inline = [
      "mv /tmp/images ~/",
      "mv /tmp/harbor-configuration.sh ~/",
      "mv /tmp/images.txt ~/"
    ]
  }

  provisioner "shell" {
    environment_vars = [
        "version=${var.harbor_version}"
    ]
    scripts = [
      "harbor-image-build.sh"
    ]
  }
}
