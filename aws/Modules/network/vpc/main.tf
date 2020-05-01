locals {
  max_subnet_length = max(
    length(var.private_subnets),
    length(var.ecodass_subnets),
    length(var.rds_subnets),
    length(var.apps_subnets),
  )
  nat_gateway_count = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(var.azs) : local.max_subnet_length

  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id = element(
    concat(
      aws_vpc_ipv4_cidr_block_association.this.*.vpc_id,
      aws_vpc.this.*.id,
      [""],
    ),
    0,
  )

  vpce_tags = merge(
    var.tags,
    var.vpc_endpoint_tags,
  )
}

######
# VPC
######
resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0

  cidr_block                       = var.cidr
  instance_tenancy                 = var.instance_tenancy
  enable_dns_hostnames             = var.enable_dns_hostnames
  enable_dns_support               = var.enable_dns_support
  enable_classiclink               = var.enable_classiclink
  enable_classiclink_dns_support   = var.enable_classiclink_dns_support
  assign_generated_ipv6_cidr_block = var.enable_ipv6

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.vpc_tags,
  )
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = var.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0

  vpc_id = aws_vpc.this[0].id

  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

###################
# DHCP Options Set
###################
resource "aws_vpc_dhcp_options" "this" {
  count = var.create_vpc && var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.dhcp_options_tags,
  )
}

###############################
# DHCP Options Set Association
###############################
resource "aws_vpc_dhcp_options_association" "this" {
  count = var.create_vpc && var.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

###################
# Internet Gateway
###################
resource "aws_internet_gateway" "this" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.igw_tags,
  )
}

resource "aws_egress_only_internet_gateway" "this" {
  count = var.create_vpc && var.enable_ipv6 && local.max_subnet_length > 0 ? 1 : 0

  vpc_id = local.vpc_id
}

################
# Publiс routes
################
resource "aws_route_table" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s-${var.public_subnet_suffix}", var.name)
    },
    var.tags,
    var.public_route_table_tags,
  )
}

resource "aws_route" "public_internet_gateway" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_internet_gateway_ipv6" {
  count = var.create_vpc && var.enable_ipv6 && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

#################
# Private routes
# There are as many routing tables as the number of NAT gateways
#################
resource "aws_route_table" "private" {
  count = var.create_vpc && local.max_subnet_length > 0 ? local.nat_gateway_count : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = var.single_nat_gateway ? "${var.name}-${var.private_subnet_suffix}" : format(
        "%s-${var.private_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.private_route_table_tags,
  )

  lifecycle {
    # When attaching VPN gateways it is common to define aws_vpn_gateway_route_propagation
    # resources that manipulate the attributes of the routing table (typically for the private subnets)
    ignore_changes = [propagating_vgws]
  }
}

#################
# Database routes
#################
resource "aws_route_table" "database" {
  count = var.create_vpc && var.create_database_subnet_route_table && length(var.rds_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    var.database_route_table_tags,
    {
      "Name" = "${var.name}-${var.database_subnet_suffix}"
    },
  )
}

resource "aws_route" "database_internet_gateway" {
  count = var.create_vpc && var.create_database_subnet_route_table && length(var.rds_subnets) > 0 && var.create_database_internet_gateway_route && false == var.create_database_nat_gateway_route ? 1 : 0

  route_table_id         = aws_route_table.database[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_nat_gateway" {
  count = var.create_vpc && var.create_database_subnet_route_table && length(var.rds_subnets) > 0 && false == var.create_database_internet_gateway_route && var.create_database_nat_gateway_route && var.enable_nat_gateway ? local.nat_gateway_count : 0

  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this.*.id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_ipv6_egress" {
  count = var.create_vpc && var.enable_ipv6 && var.create_database_subnet_route_table && length(var.rds_subnets) > 0 && var.create_database_internet_gateway_route ? 1 : 0

  route_table_id              = aws_route_table.database[0].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

#################
# Apps routes
#################
resource "aws_route_table" "apps" {
  count = var.create_vpc && var.create_apps_subnet_route_table && length(var.apps_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    var.apps_route_table_tags,
    {
      "Name" = "${var.name}-${var.apps_subnet_suffix}"
    },
  )
}

#################
# MGMT routes
#################
resource "aws_route_table" "mgmt" {
  count = var.create_vpc && var.create_mgmt_subnet_route_table && length(var.mgmt_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    var.mgmt_route_table_tags,
    {
      "Name" = "${var.name}-${var.mgmt_subnet_suffix}"
    },
  )
}
#################
# Elasticache routes
#################
resource "aws_route_table" "ecodass" {
  count = var.create_vpc && var.create_ecodass_subnet_route_table && length(var.ecodass_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    var.ecodass_route_table_tags,
    {
      "Name" = "${var.name}-${var.ecodass_subnet_suffix}"
    },
  )
}

#################
# Intra routes
#################
resource "aws_route_table" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = "${var.name}-${var.intra_subnet_suffix}"
    },
    var.tags,
    var.intra_route_table_tags,
  )
}

################
# Public subnet
################
resource "aws_subnet" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 && (false == var.one_nat_gateway_per_az || length(var.public_subnets) >= length(var.azs)) ? length(var.public_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = element(concat(var.public_subnets, [""]), count.index)
  availability_zone               = element(var.azs, count.index)
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.public_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.public_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.public_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.public_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.public_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.public_subnet_tags,
  )
}

#################
# Private subnet
#################
resource "aws_subnet" "private" {
  count = var.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.private_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.private_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.private_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.private_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.private_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.private_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.private_subnet_tags,
  )
}

##################
# Database subnet
##################
resource "aws_subnet" "database" {
  count = var.create_vpc && length(var.rds_subnets) > 0 ? length(var.rds_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.rds_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.database_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.database_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.database_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.database_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.database_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.database_subnet_tags,
  )
}

resource "aws_db_subnet_group" "database" {
  count = var.create_vpc && length(var.rds_subnets) > 0 && var.create_rds_subnet_group ? 1 : 0

  name        = lower(var.name)
  description = "Database subnet group for ${var.name}"
  subnet_ids  = aws_subnet.database.*.id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.database_subnet_group_tags,
  )
}

##################
# Apps subnet
##################
resource "aws_subnet" "apps" {
  count = var.create_vpc && length(var.apps_subnets) > 0 ? length(var.apps_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.apps_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.apps_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.apps_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.apps_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.apps_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.apps_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.apps_subnet_tags,
  )
}

##################
# MGMT subnet
##################
resource "aws_subnet" "mgmt" {
  count = var.create_vpc && length(var.mgmt_subnets) > 0 ? length(var.mgmt_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.mgmt_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.mgmt_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.mgmt_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.mgmt_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.mgmt_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.mgmt_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.mgmt_subnet_tags,
  )
}

#####################
# ElastiCache subnet
#####################
resource "aws_subnet" "ecodass" {
  count = var.create_vpc && length(var.ecodass_subnets) > 0 ? length(var.ecodass_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.ecodass_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.ecodass_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.ecodass_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.ecodass_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.ecodass_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.ecodass_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.ecodass_subnet_tags,
  )
}


#####################################################
# intra subnets - private subnet without NAT gateway
#####################################################
resource "aws_subnet" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.intra_subnets[count.index]
  availability_zone               = element(var.azs, count.index)
  assign_ipv6_address_on_creation = var.intra_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.intra_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.intra_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.intra_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "%s-${var.intra_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.intra_subnet_tags,
  )
}

#######################
# Default Network ACLs
#######################
resource "aws_default_network_acl" "this" {
  count = var.create_vpc && var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = element(concat(aws_vpc.this.*.default_network_acl_id, [""]), 0)

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      action          = ingress.value.action
      cidr_block      = lookup(ingress.value, "cidr_block", null)
      from_port       = ingress.value.from_port
      icmp_code       = lookup(ingress.value, "icmp_code", null)
      icmp_type       = lookup(ingress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(ingress.value, "ipv6_cidr_block", null)
      protocol        = ingress.value.protocol
      rule_no         = ingress.value.rule_no
      to_port         = ingress.value.to_port
    }
  }
  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      action          = egress.value.action
      cidr_block      = lookup(egress.value, "cidr_block", null)
      from_port       = egress.value.from_port
      icmp_code       = lookup(egress.value, "icmp_code", null)
      icmp_type       = lookup(egress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(egress.value, "ipv6_cidr_block", null)
      protocol        = egress.value.protocol
      rule_no         = egress.value.rule_no
      to_port         = egress.value.to_port
    }
  }

  tags = merge(
    {
      "Name" = format("%s", var.default_network_acl_name)
    },
    var.tags,
    var.default_network_acl_tags,
  )

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

########################
# Public Network ACLs
########################
resource "aws_network_acl" "public" {
  count = var.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.public.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.public_subnet_suffix}", var.name)
    },
    var.tags,
    var.public_acl_tags,
  )
}

resource "aws_network_acl_rule" "public_inbound" {
  count = var.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? length(var.public_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.public[0].id

  egress          = false
  rule_number     = var.public_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.public_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.public_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.public_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.public_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.public_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.public_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.public_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.public_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "public_outbound" {
  count = var.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? length(var.public_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.public[0].id

  egress          = true
  rule_number     = var.public_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.public_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.public_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.public_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.public_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.public_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.public_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.public_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.public_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

#######################
# Private Network ACLs
#######################
resource "aws_network_acl" "private" {
  count = var.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.private.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.private_subnet_suffix}", var.name)
    },
    var.tags,
    var.private_acl_tags,
  )
}

resource "aws_network_acl_rule" "private_inbound" {
  count = var.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? length(var.private_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.private[0].id

  egress          = false
  rule_number     = var.private_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.private_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.private_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.private_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.private_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.private_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.private_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.private_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.private_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "private_outbound" {
  count = var.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? length(var.private_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.private[0].id

  egress          = true
  rule_number     = var.private_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.private_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.private_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.private_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.private_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.private_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.private_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.private_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.private_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

########################
# Intra Network ACLs
########################
resource "aws_network_acl" "intra" {
  count = var.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.intra.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.intra_subnet_suffix}", var.name)
    },
    var.tags,
    var.intra_acl_tags,
  )
}

resource "aws_network_acl_rule" "intra_inbound" {
  count = var.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? length(var.intra_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.intra[0].id

  egress          = false
  rule_number     = var.intra_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.intra_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.intra_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.intra_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.intra_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.intra_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.intra_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.intra_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.intra_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "intra_outbound" {
  count = var.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? length(var.intra_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.intra[0].id

  egress          = true
  rule_number     = var.intra_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.intra_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.intra_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.intra_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.intra_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.intra_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.intra_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.intra_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.intra_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

########################
# Database Network ACLs
########################
resource "aws_network_acl" "database" {
  count = var.create_vpc && var.database_dedicated_network_acl && length(var.rds_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.database.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.database_subnet_suffix}", var.name)
    },
    var.tags,
    var.database_acl_tags,
  )
}

resource "aws_network_acl_rule" "database_inbound" {
  count = var.create_vpc && var.database_dedicated_network_acl && length(var.rds_subnets) > 0 ? length(var.database_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.database[0].id

  egress          = false
  rule_number     = var.database_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.database_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.database_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.database_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.database_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.database_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.database_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.database_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.database_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "database_outbound" {
  count = var.create_vpc && var.database_dedicated_network_acl && length(var.rds_subnets) > 0 ? length(var.database_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.database[0].id

  egress          = true
  rule_number     = var.database_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.database_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.database_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.database_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.database_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.database_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.database_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.database_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.database_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

########################
# Apps Network ACLs
########################
resource "aws_network_acl" "apps" {
  count = var.create_vpc && var.apps_dedicated_network_acl && length(var.apps_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.apps.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.apps_subnet_suffix}", var.name)
    },
    var.tags,
    var.apps_acl_tags,
  )
}

resource "aws_network_acl_rule" "apps_inbound" {
  count = var.create_vpc && var.apps_dedicated_network_acl && length(var.apps_subnets) > 0 ? length(var.apps_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.apps[0].id

  egress          = false
  rule_number     = var.apps_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.apps_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.apps_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.apps_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.apps_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.apps_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.apps_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.apps_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.apps_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "apps_outbound" {
  count = var.create_vpc && var.apps_dedicated_network_acl && length(var.apps_subnets) > 0 ? length(var.apps_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.apps[0].id

  egress          = true
  rule_number     = var.apps_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.apps_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.apps_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.apps_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.apps_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.apps_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.apps_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.apps_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.apps_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

########################
# MGMT Network ACLs
########################
resource "aws_network_acl" "mgmt" {
  count = var.create_vpc && var.mgmt_dedicated_network_acl && length(var.mgmt_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.mgmt.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.mgmt_subnet_suffix}", var.name)
    },
    var.tags,
    var.mgmt_acl_tags,
  )
}



resource "aws_network_acl_rule" "mgmt_inbound" {
  count = var.create_vpc && var.mgmt_dedicated_network_acl && length(var.mgmt_subnets) > 0 ? length(var.mgmt_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.mgmt[0].id

  egress          = false
  rule_number     = var.mgmt_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.mgmt_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.mgmt_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.mgmt_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.mgmt_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.mgmt_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.mgmt_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.mgmt_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.mgmt_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "mgmt_outbound" {
  count = var.create_vpc && var.mgmt_dedicated_network_acl && length(var.mgmt_subnets) > 0 ? length(var.mgmt_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.mgmt[0].id

  egress          = true
  rule_number     = var.mgmt_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.mgmt_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.mgmt_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.mgmt_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.mgmt_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.mgmt_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.mgmt_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.mgmt_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.mgmt_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

###########################
# Elasticache Network ACLs
###########################
resource "aws_network_acl" "ecodass" {
  count = var.create_vpc && var.ecodass_dedicated_network_acl && length(var.ecodass_subnets) > 0 ? 1 : 0

  vpc_id     = element(concat(aws_vpc.this.*.id, [""]), 0)
  subnet_ids = aws_subnet.ecodass.*.id

  tags = merge(
    {
      "Name" = format("%s-${var.ecodass_subnet_suffix}", var.name)
    },
    var.tags,
    var.ecodass_acl_tags,
  )
}

resource "aws_network_acl_rule" "ecodass_inbound" {
  count = var.create_vpc && var.ecodass_dedicated_network_acl && length(var.ecodass_subnets) > 0 ? length(var.ecodass_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.ecodass[0].id

  egress          = false
  rule_number     = var.ecodass_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.ecodass_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.ecodass_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.ecodass_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.ecodass_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.ecodass_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.ecodass_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.ecodass_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.ecodass_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "ecodass_outbound" {
  count = var.create_vpc && var.ecodass_dedicated_network_acl && length(var.ecodass_subnets) > 0 ? length(var.ecodass_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.ecodass[0].id

  egress          = true
  rule_number     = var.ecodass_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.ecodass_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.ecodass_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.ecodass_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.ecodass_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.ecodass_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.ecodass_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.ecodass_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.ecodass_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

##############
# NAT Gateway
##############
# Workaround for interpolation not being able to "short-circuit" the evaluation of the conditional branch that doesn't end up being used
# Source: https://github.com/hashicorp/terraform/issues/11566#issuecomment-289417805
#
# The logical expression would be
#
#    nat_gateway_ips = var.reuse_nat_ips ? var.external_nat_ip_ids : aws_eip.nat.*.id
#
# but then when count of aws_eip.nat.*.id is zero, this would throw a resource not found error on aws_eip.nat.*.id.
locals {
  nat_gateway_ips = split(
    ",",
    var.reuse_nat_ips ? join(",", var.external_nat_ip_ids) : join(",", aws_eip.nat.*.id),
  )
}

resource "aws_eip" "nat" {
  count = var.create_vpc && var.enable_nat_gateway && false == var.reuse_nat_ips ? local.nat_gateway_count : 0

  vpc = true

  tags = merge(
    {
      "Name" = format(
        "%s-%s",
        var.name,
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_eip_tags,
  )
}

resource "aws_nat_gateway" "this" {
  count = var.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(
    local.nat_gateway_ips,
    var.single_nat_gateway ? 0 : count.index,
  )
  subnet_id = element(
    aws_subnet.public.*.id,
    var.single_nat_gateway ? 0 : count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "%s-%s",
        var.name,
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_gateway_tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = var.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this.*.id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "private_ipv6_egress" {
  count = var.create_vpc && var.enable_ipv6 ? length(var.private_subnets) : 0

  route_table_id              = element(aws_route_table.private.*.id, count.index)
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = element(aws_egress_only_internet_gateway.this.*.id, 0)
}

##########################
# Route table association
##########################
resource "aws_route_table_association" "private" {
  count = var.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  subnet_id = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(
    aws_route_table.private.*.id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "database" {
  count = var.create_vpc && length(var.rds_subnets) > 0 ? length(var.rds_subnets) : 0

  subnet_id = element(aws_subnet.database.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.database.*.id, aws_route_table.private.*.id),
    var.single_nat_gateway || var.create_database_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "apps" {
  count = var.create_vpc && length(var.apps_subnets) > 0 && false == var.enable_public_apps ? length(var.apps_subnets) : 0

  subnet_id = element(aws_subnet.apps.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.apps.*.id, aws_route_table.private.*.id),
    var.single_nat_gateway || var.create_apps_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "mgmt" {
  count = var.create_vpc && length(var.mgmt_subnets) > 0 && false == var.enable_public_mgmt ? length(var.mgmt_subnets) : 0

  subnet_id = element(aws_subnet.mgmt.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.mgmt.*.id, aws_route_table.private.*.id),
    var.single_nat_gateway || var.create_mgmt_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "apps_public" {
  count = var.create_vpc && length(var.apps_subnets) > 0 && var.enable_public_apps ? length(var.apps_subnets) : 0

  subnet_id = element(aws_subnet.apps.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.apps.*.id, aws_route_table.public.*.id),
    var.single_nat_gateway || var.create_apps_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "mgmt_public" {
  count = var.create_vpc && length(var.mgmt_subnets) > 0 && var.enable_public_mgmt ? length(var.mgmt_subnets) : 0

  subnet_id = element(aws_subnet.mgmt.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.mgmt.*.id, aws_route_table.public.*.id),
    var.single_nat_gateway || var.create_mgmt_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "ecodass" {
  count = var.create_vpc && length(var.ecodass_subnets) > 0 ? length(var.ecodass_subnets) : 0

  subnet_id = element(aws_subnet.ecodass.*.id, count.index)
  route_table_id = element(
    coalescelist(
      aws_route_table.ecodass.*.id,
      aws_route_table.private.*.id,
    ),
    var.single_nat_gateway || var.create_ecodass_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  subnet_id      = element(aws_subnet.intra.*.id, count.index)
  route_table_id = element(aws_route_table.intra.*.id, 0)
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? length(var.public_subnets) : 0

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public[0].id
}

####################
# Customer Gateways
####################
resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  bgp_asn    = each.value["bgp_asn"]
  ip_address = each.value["ip_address"]
  type       = "ipsec.1"

  tags = merge(
    {
      Name = format("%s-%s", var.name, each.key)
    },
    var.tags,
    var.customer_gateway_tags,
  )
}

##############
# VPN Gateway
##############
resource "aws_vpn_gateway" "this" {
  count = var.create_vpc && var.enable_vpn_gateway ? 1 : 0

  vpc_id          = local.vpc_id
  amazon_side_asn = var.amazon_side_asn

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.vpn_gateway_tags,
  )
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.vpn_gateway_id != "" ? 1 : 0

  vpc_id         = local.vpc_id
  vpn_gateway_id = var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count = var.create_vpc && var.propagate_public_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? 1 : 0

  route_table_id = element(aws_route_table.public.*.id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this.*.id,
      aws_vpn_gateway_attachment.this.*.vpn_gateway_id,
    ),
    count.index,
  )
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count = var.create_vpc && var.propagate_private_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? length(var.private_subnets) : 0

  route_table_id = element(aws_route_table.private.*.id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this.*.id,
      aws_vpn_gateway_attachment.this.*.vpn_gateway_id,
    ),
    count.index,
  )
}

###########
# Defaults
###########
resource "aws_default_vpc" "this" {
  count = var.manage_default_vpc ? 1 : 0

  enable_dns_support   = var.default_vpc_enable_dns_support
  enable_dns_hostnames = var.default_vpc_enable_dns_hostnames
  enable_classiclink   = var.default_vpc_enable_classiclink

  tags = merge(
    {
      "Name" = format("%s", var.default_vpc_name)
    },
    var.tags,
    var.default_vpc_tags,
  )
}
