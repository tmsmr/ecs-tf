locals {
  name_prefix    = "ecs-tf"
  vpc_cidr_block = "10.0.0.0/16"
  node_type      = "t3.micro"
  asg_min        = 2
  asg_desired    = 2
  asg_max        = 2
  task_cpu       = 256
  task_memory    = 128
}

resource random_pet "deployment_id" {
  length    = 2
  separator = "-"
}

### TEST DEPLOYMENT ###

# service connect namespace
resource "aws_service_discovery_http_namespace" "test_deployment_namespace" {
  name = "${local.name_prefix}-${random_pet.deployment_id.id}-test-deployment"
}

# upstream service https://github.com/tmsmr/context
resource "aws_ecs_task_definition" "ecs_context_task_definition" {
  family             = "context"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  cpu                = local.task_cpu
  memory             = local.task_memory
  container_definitions = jsonencode([
    {
      name      = "context"
      image     = "ghcr.io/tmsmr/context:latest"
      cpu       = local.task_cpu
      memory    = local.task_memory
      essential = true
      portMappings = [
        {
          name          = "httpalt"
          containerPort = 8080
          hostPort = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = "context"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ecs_context_service" {
  name            = "context"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_context_task_definition.arn
  desired_count   = 1
  network_configuration {
    subnets = aws_subnet.ecs_private.*.id
    security_groups = [aws_security_group.ecs_security_group_private.id]
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 100
  }
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.test_deployment_namespace.arn
    service {
      discovery_name = "context"
      port_name      = "httpalt"
      client_alias {
        dns_name = "context"
        port     = 8080
      }
    }
  }
  depends_on = [aws_autoscaling_group.ecs_asg]
}

# proxy with socat
resource "aws_ecs_task_definition" "ecs_socat_task_definition" {
  family             = "socat"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  cpu                = local.task_cpu
  memory             = local.task_memory
  container_definitions = jsonencode([
    {
      name      = "socat"
      image     = "alpine/socat:latest"
      cpu       = local.task_cpu
      memory    = local.task_memory
      essential = true
      command = ["tcp-listen:8080,fork,reuseaddr", "tcp-connect:context:8080"],
      portMappings = [
        {
          name          = "httpalt"
          containerPort = 8080
          hostPort = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = "socat"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "ecs_socat_service" {
  name            = "socat"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_socat_task_definition.arn
  desired_count   = 1
  network_configuration {
    subnets = aws_subnet.ecs_private.*.id
    security_groups = [aws_security_group.ecs_security_group_private.id]
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
    weight            = 100
  }
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.test_deployment_namespace.arn
    service {
      discovery_name = "socat"
      port_name      = "httpalt"
      client_alias {
        dns_name = "socat"
        port     = 8080
      }
    }
  }
  depends_on = [aws_autoscaling_group.ecs_asg]
}
