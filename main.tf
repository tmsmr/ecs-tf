locals {
  name_prefix    = "ecs-tf"
  vpc_cidr_block = "10.0.0.0/16"
  node_type      = "t3.micro"
  asg_min        = 1
  asg_desired    = 1
  asg_max        = 3
}

resource random_pet "deployment_id" {
  length    = 2
  separator = "-"
}
