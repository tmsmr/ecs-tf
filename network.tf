resource "aws_vpc" "ecs_vpc" {
  cidr_block           = local.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-vpc"
  }
}

# prune and rename the default route table
resource "aws_default_route_table" "ecs_vpc_default_rt" {
  default_route_table_id = aws_vpc.ecs_vpc.default_route_table_id
  route = []
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-unused"
  }
}

data "aws_availability_zones" "azs" {}

# public subnet in each AZ
resource "aws_subnet" "ecs_public" {
  count = length(data.aws_availability_zones.azs.names)
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block = cidrsubnet(local.vpc_cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-${data.aws_availability_zones.azs.names[count.index]}-public"
  }
}

# internet gateway for the public subnets
resource "aws_internet_gateway" "ecs_igw" {
  vpc_id = aws_vpc.ecs_vpc.id
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-igw"
  }
}

# route table for the public subnets
resource "aws_route_table" "ecs_public_rt" {
  vpc_id = aws_vpc.ecs_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_igw.id
  }
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-rt"
  }
}

resource "aws_route_table_association" "ecs_public_rt_attachment" {
  count = length(data.aws_availability_zones.azs.names)
  subnet_id      = aws_subnet.ecs_public[count.index].id
  route_table_id = aws_route_table.ecs_public_rt.id
}

# private subnets in each AZ
resource "aws_subnet" "ecs_private" {
  count = length(data.aws_availability_zones.azs.names)
  vpc_id            = aws_vpc.ecs_vpc.id
  cidr_block = cidrsubnet(local.vpc_cidr_block, 8, count.index + 3)
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-${data.aws_availability_zones.azs.names[count.index]}-private"
  }
}

# NAT gateways for the private subnets
resource "aws_eip" "nat_gw_eip" {
  count = length(data.aws_availability_zones.azs.names)
}

resource "aws_nat_gateway" "nat_gw" {
  count = length(data.aws_availability_zones.azs.names)
  allocation_id = aws_eip.nat_gw_eip[count.index].id
  subnet_id     = aws_subnet.ecs_public[count.index].id
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-${data.aws_availability_zones.azs.names[count.index]}-gw"
  }
}

# route tables for the private subnets
resource "aws_route_table" "ecs_private_rt" {
  count = length(data.aws_availability_zones.azs.names)
  vpc_id = aws_vpc.ecs_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id
  }
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-${data.aws_availability_zones.azs.names[count.index]}-private-rt"
  }
}

resource "aws_route_table_association" "ecs_private_rt_attachment" {
  count = length(data.aws_availability_zones.azs.names)
  subnet_id      = aws_subnet.ecs_private[count.index].id
  route_table_id = aws_route_table.ecs_private_rt[count.index].id
}
