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
  volume_size   = 30
  source_ami    = "ami-0c2ab3b8efb09f272"
  ami_name      = "ami-snow-harbor"
  harbor_version= "v2.7.0"
}

source "amazon-ebs" "harbor-al2" {
  ami_name      = var.ami_name
  source_ami    = var.source_ami
  instance_type = var.instance_type
  region        = var.region
  ssh_username  = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_size
    delete_on_termination = true
  }
}

build {
  sources = [
    "source.amazon-ebs.harbor-al2"
  ]

  provisioner "shell-local" {
    inline = [
      "old='/'",
      "new='-'",
      "cat images.txt | while read image || [[ -n $image ]]; do sudo docker pull $image && newout=$(echo $image | sed 's/\\$old/\\$new/g') && sudo docker save $image > images/$newout.tar; done"
    ]
  }

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
