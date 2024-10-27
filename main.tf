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

# upstream http service (nginx)
resource "aws_ecs_task_definition" "ecs_nginx_task_definition" {
  family             = "nginx"
  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  cpu                = local.task_cpu
  memory             = local.task_memory
  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "nginx:latest"
      cpu       = local.task_cpu
      memory    = local.task_memory
      essential = true
      portMappings = [
        {
          name          = "http"
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = "nginx"
        }
      }
      healthcheck = {
        command = ["CMD-SHELL", "curl -f http://localhost:80/ || exit 1"]
        interval    = 10
        timeout     = 5
        startPeriod = 60
        retries     = 3
      }
    }
  ])
}

resource "aws_ecs_service" "ecs_nginx_service" {
  name            = "nginx"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_nginx_task_definition.arn
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
      discovery_name = "nginx"
      port_name      = "http"
      client_alias {
        dns_name = "nginx"
        port     = 80
      }
    }
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_nginx_target_group.arn
    container_name   = "nginx"
    container_port   = 80
  }
  depends_on = [aws_autoscaling_group.ecs_asg, aws_lb_listener.alb_http_listener]
}

resource "aws_lb_target_group" "ecs_nginx_target_group" {
  name        = "nginx-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.ecs_vpc.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener_rule" "nginx_listener_rule" {
  listener_arn = aws_lb_listener.alb_http_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_nginx_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/", "/*"]
    }
  }
}


# proxy with socat
# resource "aws_ecs_task_definition" "ecs_socat_task_definition" {
#   family             = "socat"
#   network_mode       = "awsvpc"
#   execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
#   cpu                = local.task_cpu
#   memory             = local.task_memory
#   container_definitions = jsonencode([
#     {
#       name      = "socat"
#       image     = "alpine/socat:latest"
#       cpu       = local.task_cpu
#       memory    = local.task_memory
#       essential = true
#       command = ["tcp-listen:8080,fork,reuseaddr", "tcp-connect:context:8080"],
#       portMappings = [
#         {
#           name          = "httpalt"
#           containerPort = 8080
#           hostPort      = 8080
#           protocol      = "tcp"
#         }
#       ]
#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
#           "awslogs-region"        = "eu-central-1"
#           "awslogs-stream-prefix" = "socat"
#         }
#       }
#     }
#   ])
# }
#
# resource "aws_ecs_service" "ecs_socat_service" {
#   name            = "socat"
#   cluster         = aws_ecs_cluster.ecs_cluster.id
#   task_definition = aws_ecs_task_definition.ecs_socat_task_definition.arn
#   desired_count   = 0
#   network_configuration {
#     subnets = aws_subnet.ecs_private.*.id
#     security_groups = [aws_security_group.ecs_security_group_private.id]
#   }
#   capacity_provider_strategy {
#     capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
#     weight            = 100
#   }
#   service_connect_configuration {
#     enabled   = true
#     namespace = aws_service_discovery_http_namespace.test_deployment_namespace.arn
#     service {
#       discovery_name = "socat"
#       port_name      = "httpalt"
#       client_alias {
#         dns_name = "socat"
#         port     = 8080
#       }
#     }
#   }
#   depends_on = [aws_autoscaling_group.ecs_asg, aws_lb_listener.alb_http_listener]
# }
