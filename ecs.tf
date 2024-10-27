resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-cluster"
}

# IAM role/profile for the ECS nodes
resource "aws_iam_role" "ecs_instance_role" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-instance-role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ecs_instance_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_cloudwatch_role" {
  role       = aws_iam_role.ecs_instance_role.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# ecs image provided by aws
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

# sg to allow all traffic (to be used in private subnets)
resource "aws_security_group" "ecs_security_group_private" {
  name   = "${local.name_prefix}-${random_pet.deployment_id.id}-security-group-private"
  vpc_id = aws_vpc.ecs_vpc.id
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# launch template for the ECS nodes
resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "${local.name_prefix}-${random_pet.deployment_id.id}-node-template"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = local.node_type
  vpc_security_group_ids = [aws_security_group.ecs_security_group_private.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-${random_pet.deployment_id.id}-instance"
    }
  }
  user_data = base64encode(templatefile("ecs-config.sh.tpl", {
    cluster_name = aws_ecs_cluster.ecs_cluster.name
  }))
}

# autoscaling group for the ECS nodes
resource "aws_autoscaling_group" "ecs_asg" {
  vpc_zone_identifier = aws_subnet.ecs_private.*.id
  desired_capacity    = local.asg_desired
  max_size            = local.asg_max
  min_size            = local.asg_min
  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# capacity provider for the ECS cluster
resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
  name = "capacity-provider-${local.name_prefix}-${random_pet.deployment_id.id}"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = local.asg_max
    }
  }
}

# capacity provider strategy for the ECS cluster
resource "aws_ecs_cluster_capacity_providers" "ecs_cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.ecs_cluster.name

  capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  }
}

# task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-task-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_tasks_execution_role_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-log-group"
}
