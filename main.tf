provider "aws" {
  alias  = "us"
  region = "us-west-1"
}

provider "aws" {
  alias  = "network-us"
  region = "us-west-1"
}

provider "aws" {
  alias  = "network-sg"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "sg"
  region = "ap-southeast-1"
}

########### US-APPS - VPC - SUBNET - DATA SOURCE ############

data "aws_vpc" "us-apps-vpc-np" {
  provider = "aws.us"
  tags = {
    Name = "us-apps-vpc-np"
  }
}

data "aws_subnet_ids" "all_us_1a" {
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   provider = aws.us
   tags = {
    Name = "us-apps-vpc-np-apps-us-west-1a"
  }
}

data "aws_subnet_ids" "all_us_1b" {
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   provider = aws.us
   tags = {
    Name = "us-apps-vpc-np-apps-us-west-1b"
  }
}

########### SG-APPS - VPC - SUBNET - DATA SOURCE ############

data "aws_vpc" "sg-apps-vpc-np" {
  provider = "aws.sg"
  tags = {
    Name = "sg-apps-vpc-np"
  }
}

data "aws_subnet_ids" "all_sg_1a" {
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   provider = aws.sg
   tags = {
    Name = "sg-apps-vpc-np-apps-ap-southeast-1a"
  }
}

data "aws_subnet_ids" "all_sg_1b" {
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   provider = aws.sg
   tags = {
    Name = "sg-apps-vpc-np-apps-ap-southeast-1b"
  }
}

########### US-MGMT - VPC - SUBNET - DATA SOURCE ############

data "aws_vpc" "us-mgmt-vpc-np" {
  provider = "aws.network-us"
  tags = {
    Name = "us-mgmt-vpc-np"
  }
}

data "aws_subnet_ids" "jmp_us_1a" {
   vpc_id = data.aws_vpc.us-mgmt-vpc-np.id
   provider = aws.network-us
   tags = {
    Name = "us-mgmt-vpc-np-private-us-west-1a"
  }
}

data "aws_subnet_ids" "jmp_us_1b" {
   vpc_id = data.aws_vpc.us-mgmt-vpc-np.id
   provider = aws.network-us
   tags = {
    Name = "us-mgmt-vpc-np-private-us-west-1b"
  }
}

########### SG-MGMT - VPC - SUBNET - DATA SOURCE ############

data "aws_vpc" "sg-mgmt-vpc-np" {
  provider = "aws.network-sg"
  tags = {
    Name = "sg-mgmt-vpc-np"
  }
}

data "aws_subnet_ids" "jmp_sg_1a" {
   vpc_id = data.aws_vpc.sg-mgmt-vpc-np.id
   provider = aws.network-sg
   tags = {
    Name = "sg-mgmt-vpc-np-private-ap-southeast-1a"
  }
}

data "aws_subnet_ids" "jmp_sg_1b" {
   vpc_id = data.aws_vpc.sg-mgmt-vpc-np.id
   provider = aws.network-sg
   tags = {
    Name = "sg-mgmt-vpc-np-private-ap-southeast-1b"
  }
}


##################################################################
# US Data sources to get Securitygroups details
##################################################################

data "aws_security_group" "SG-WorkerNodes" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   tags = {
    Name = "SG-WorkerNodes"
  }
}
data "aws_security_group" "SG-Identity" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   tags = {
    Name = "SG-Identity"
  }
}
data "aws_security_group" "SG-Platform-Kafka" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   tags = {
    Name = "SG-Platform-Kafka"
  }
}
data "aws_security_group" "SG-Platform-Elastic" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   tags = {
    Name = "SG-Platform-Elastic"
  }
}
data "aws_security_group" "SG-Platform-EcoDaas" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-rds-vpc-np.id
   tags = {
    Name = "SG-Platform-EcoDaas"
  }
}
data "aws_security_group" "SG-Spark" {
   provider = aws.us
   vpc_id = data.aws_vpc.us-apps-vpc-np.id
   tags = {
    Name = "SG-Spark"
  }
}

###################################################
#   SG Data sources to get Securitygroups details
###################################################

data "aws_security_group" "SG-WorkerNodes-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   tags = {
    Name = "SG-WorkerNodes-sing"
  }
}
data "aws_security_group" "SG-Identity-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   tags = {
    Name = "SG-Identity-sing"
  }
}
data "aws_security_group" "SG-Platform-Kafka-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   tags = {
    Name = "SG-Platform-Kafka-sing"
  }
}
data "aws_security_group" "SG-Platform-Elastic-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   tags = {
    Name = "SG-Platform-Elastic-sing"
  }
}
data "aws_security_group" "SG-Platform-EcoDaas-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-rds-vpc-np.id
   tags = {
    Name = "SG-Platform-EcoDaas-sing"
  }
}
data "aws_security_group" "SG-Spark-sing" {
   provider = aws.sg
   vpc_id = data.aws_vpc.sg-apps-vpc-np.id
   tags = {
    Name = "SG-Spark-sing"
  }
}



##################################################################
# US Data sources to get AMI details
##################################################################

data "aws_ami" "amazon_linux_us" {
  provider = aws.us
  most_recent = true

  owners = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn2-ami-hvm-2.0.20191217.0-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

data "aws_availability_zones" "available_us" {
  provider = aws.us
  state = "available"
}

##################################################################
# SG Data sources to get AMI details
##################################################################

data "aws_ami" "amazon_linux_sg" {
  provider = aws.sg
  most_recent = true

  owners = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn2-ami-hvm-2.0.20191217.0-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

data "aws_availability_zones" "available_sg" {
  provider = aws.sg
  state = "available"
}



################################################################
#         SSH-KEY-GENERATE
################################################################

#resource "tls_private_key" "sshkey" {
#  algorithm = "RSA"
#  rsa_bits  = 4096

#}

#resource "aws_key_pair" "generated_key" {
#  key_name   = var.key_name
#  public_key = tls_private_key.sshkey.public_key_openssh

#}

####################################################################
#                  EFS
####################################################################

  resource "aws_efs_file_system" "efs" {
    creation_token   = "EFS Shared Data"
    performance_mode = "generalPurpose"tags = {
      Name = "EFS Shared Data"
    }
    }

  resource "aws_efs_mount_target" "efs" {
  file_system_id  = "${aws_efs_file_system.efs.id}"
  subnet_id       = tolist(data.aws_subnet_ids.all_us_1a.ids,data.aws_subnet_ids.all_us_1b.ids)[0]
  security_groups = "${data.aws_security_group.SG-WorkerNodes.id}"
  }


####################################################################
#        Insight EMS Server ZONE-A
####################################################################

module "ecp-workernode" {
  source = "../../../modules/compute/ec2"
  providers = {
    aws = aws.us
  }

  instance_count              = "1"
  name                        = "Insight EMS Server"
  ami                         = data.aws_ami.amazon_linux_us.id
  instance_type               = "m5.xlarge"
  security_groups	          = ["${data.aws_security_group.SG-WorkerNodes.id}"]


  subnet_id                   = tolist(data.aws_subnet_ids.all_us_1a.ids)[0]

  #key_name                    = aws_key_pair.generated_key.key_name
  key_name		      = var.key_name
  #tenancy		      = var.tenancy
  user_data = <<-EOF
                #!/bin/bash
                sleep 5m
                sudo su - root
                # Install AWS EFS Utilities
                yum install -y amazon-efs-utils
                # Mount EFS
                mkdir /efs
                efs_id="${efs_id}"
                mount -t efs $efs_id:/ /efs
                # Edit fstab so EFS automatically loads on reboot
                echo $efs_id:/ /efs efs defaults,_netdev 0 0 >> /etc/fstab
  EOF

  tags = {
    App-Name    = "Insight EMS Server"
    Components  = "workernode"
    Environment = "UAT"

   }

  root_block_device = [
    {
      volume_type = "gp2"
      volume_size = 100
      Name = "data-volume"
    }
  ]
}


resource "aws_route53_record" "worker-node-us-a" {
  provider = aws.us
  count = "11"
#  zone_id = aws_route53_zone.main.zone_id
  zone_id = "equinix.com"
  name = "worker-node-us-a${count.index}"
  type = "A"
  ttl = "300"
  records = element(module.ecp-workernode.*.private_ip, count.index)
}



####################################################################
#        Insight EMS Server -ZONE-B
####################################################################

module "ecp-workernode-b" {
  source = "../../../modules/compute/ec2"
  providers = {
    aws = aws.us
  }

  instance_count              = "11"
  name                        = "Insight EMS Server"
  ami                         = data.aws_ami.amazon_linux_us.id
  instance_type               = "m5.xlarge"
  security_groups	      = ["${data.aws_security_group.SG-WorkerNodes.id}"]


  subnet_id                   = tolist(data.aws_subnet_ids.all_us_1b.ids)[0]

  #key_name                    = aws_key_pair.generated_key.key_name
  key_name		      = var.key_name
  #tenancy		      = var.tenancy
  user_data = <<-EOF
                #!/bin/bash
                sleep 5m
                sudo su - root
                # Install AWS EFS Utilities
                yum install -y amazon-efs-utils
                # Mount EFS
                mkdir /efs
                efs_id="${efs_id}"
                mount -t efs $efs_id:/ /efs
                # Edit fstab so EFS automatically loads on reboot
                echo $efs_id:/ /efs efs defaults,_netdev 0 0 >> /etc/fstab
  EOF

  tags = {
  App-Name    = "Insight EMS Server"
  Components  = "workernode"
  Environment = "UAT"

  }

  root_block_device = [
    {
      volume_type = "gp2"
      volume_size = 100
      Name = "data-volume"
    }
  ]
}


resource "aws_route53_record" "ecp-workernode-b" {
  provider = aws.us
  count = "11"
# zone_id = aws_route53_zone.main.zone_id
  zone_id = "equinix.com"
  name = "worker-node-us-b${count.index}"
  type = "A"
  ttl = "300"
  records = element(module.ecp-workernode-b.*.private_ip, count.index)
}
