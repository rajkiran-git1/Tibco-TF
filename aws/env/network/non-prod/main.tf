provider "aws" {
  alias  = "apps-us"
  region = "us-west-1"
  assume_role {
    role_arn     = "arn:aws:iam::869243597727:role/npecp_network_role"
  }
}

provider "aws" {
  alias  = "network-us"  
  region = "us-west-1"
  assume_role {
    role_arn     = "arn:aws:iam::889406220557:role/npnw_network_role"
  }
}

provider "aws" {
  alias  = "network-sg"
  region = "ap-southeast-1"
  assume_role {
    role_arn     = "arn:aws:iam::889406220557:role/npnw_network_role"
  }
}

provider "aws" {
  alias  = "network-est"
  region = "us-east-1"
  assume_role {
    role_arn     = "arn:aws:iam::889406220557:role/npnw_network_role"
  }
}

provider "aws" {
  alias  = "apps-sg"
  region = "ap-southeast-1"
  assume_role {
    role_arn     = "arn:aws:iam::869243597727:role/npecp_network_role"
  }
}

provider "aws" {
  alias  = "iam-us"
  region = "us-west-1"
  assume_role {
    role_arn     = "arn:aws:iam::128270211494:role/npiam_network_role"
  }
}

provider "aws" {
  alias  = "iam-sg"
  region = "ap-southeast-1"
  assume_role {
    role_arn     = "arn:aws:iam::128270211494:role/npiam_network_role"
  }
}


provider "aws" {
  alias  = "iam-us-est"
  region = "us-east-1"
  assume_role {
    role_arn     = "arn:aws:iam::128270211494:role/npiam_network_role"
  }
}

provider "aws" {
  alias  = "cre-wst"
  region = "us-west-1"
  assume_role {
    role_arn     = "arn:aws:iam::885176677945:role/npsand_network_role"
  }
}

#########################
# VPC/Subnet creation   #
#########################

module "us_apps_vpc_np" {
  source                  = "../../../modules/network/vpc"
  providers = {
    aws = aws.apps-us
  }
  name                    = "us-apps-vpc-np"
  cidr                    = "10.200.128.0/20"
  instance_tenancy        = "default"
  azs                     = ["us-west-1a", "us-west-1b"]
  public_subnets          = ["10.200.128.0/26", "10.200.128.64/26"]
  apps_subnets            = ["10.200.132.0/22", "10.200.136.0/22"]

  create_rds_subnet_group = false

  enable_dns_hostnames = true
  enable_dns_support   = true

#  enable_classiclink             = true
#  enable_classiclink_dns_support = true

  enable_nat_gateway = false
  single_nat_gateway = false

  enable_vpn_gateway = false

  enable_dhcp_options              = true
  dhcp_options_domain_name         = "npclouda.equinix.com"
 # sample dhcp IP

}


module "us_rds_vpc_np" {
  source                  = "../../../modules/network/vpc"
  providers = {
    aws = aws.iam-us
  }
  name                    = "us-rds-vpc-np"
  cidr                    = "10.200.144.0/21"
  instance_tenancy        = "default"
  azs                     = ["us-west-1a", "us-west-1b"]
  rds_subnets             = ["10.200.144.0/24", "10.200.145.0/24"]
  ecodass_subnets         = ["10.200.146.0/24", "10.200.147.0/24"]

  create_rds_subnet_group = true

  enable_dns_hostnames = true
  enable_dns_support   = true

#  enable_classiclink             = true
#  enable_classiclink_dns_support = true

  enable_nat_gateway = false
  single_nat_gateway = false

  enable_vpn_gateway = false

  enable_dhcp_options              = true
  dhcp_options_domain_name         = "npclouda.equinix.com"

}

module "sg_apps_vpc_np" {
  source                  = "../../../modules/network/vpc"
  providers = {
    aws = aws.apps-sg
  }
  name                    = "sg-apps-vpc-np"
  cidr                    = "10.17.128.0/20"
  instance_tenancy        = "default"
  azs                     = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnets          = ["10.17.128.0/26", "10.17.128.64/26"]
  apps_subnets            = ["10.17.132.0/22", "10.17.136.0/22"]

  create_rds_subnet_group = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false
  single_nat_gateway = false

  enable_vpn_gateway = false

  enable_dhcp_options              = true
  dhcp_options_domain_name         = "npclouda.equinix.com"
}

module "sg_rds_vpc_np" {
  source                  = "../../../modules/network/vpc"
  providers = {
    aws = aws.iam-sg
  }
  name                    = "sg-rds-vpc-np"
  cidr                    = "10.17.144.0/23"
  instance_tenancy        = "default"
  azs                     = ["ap-southeast-1a", "ap-southeast-1b"]
  rds_subnets             = ["10.17.144.0/24", "10.17.145.0/24"]

  create_rds_subnet_group = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false
  single_nat_gateway = false

  enable_vpn_gateway = false

  enable_dhcp_options              = true
  dhcp_options_domain_name         = "npclouda.equinix.com"
}

