resource "aws_security_group" "alb_security_group" {
  name   = "${local.name_prefix}-${random_pet.deployment_id.id}-security-group-alb"
  vpc_id = aws_vpc.ecs_vpc.id
  ingress {
    from_port = 0
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 0
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "ecs_alb" {
  name               = "${local.name_prefix}-${random_pet.deployment_id.id}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_security_group.id]
  subnets            = aws_subnet.ecs_public[*].id
  tags = {
    Name = "${local.name_prefix}-${random_pet.deployment_id.id}-alb"
  }
}

resource "aws_lb_listener" "alb_http_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}
