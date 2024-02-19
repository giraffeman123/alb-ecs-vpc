provider "aws" {
    region = var.aws_region
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
}

resource "aws_ecs_cluster" "my_cluster" {
    name = "app-cluster" # Name your cluster here
}

data "aws_iam_policy_document" "assume_role_policy" {
    statement {
        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["ecs-tasks.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
    name               = "ecsTaskExecutionRole"
    assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
    role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "template_file" "task_definition" {
    template = file("${path.module}/files/task-definition.json")
    vars = {
        app_name = "${var.application}-task"
        app_port = 3000
        img_repo = "elliotmtz12/merge-sort"
    }
}

resource "aws_ecs_task_definition" "app_task" {
    family                   = "${var.application}-task" # Name your task
    container_definitions    = data.template_file.task_definition.rendered
    requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
    network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
    memory                   = 512         # Specify the memory the container requires
    cpu                      = 256         # Specify the CPU the container requires
    execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_security_group" "service_security_group" {
    vpc_id = var.vpc_id
    name        = "ecs-app-sg-${var.application}-${var.environment}"
    description = "Security Group for ECS APP ${var.application}-${var.environment}" 
    
    ingress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        # Only allowing traffic in from the load balancer security group
        security_groups = ["${var.alb_sg_id}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_ecs_service" "app_service" {
    name            = "app-first-service"     # Name the service
    cluster         = "${aws_ecs_cluster.my_cluster.id}"   # Reference the created Cluster
    task_definition = "${aws_ecs_task_definition.app_task.arn}" # Reference the task that the service will spin up
    launch_type     = "FARGATE"
    desired_count   = 3 # Set up the number of containers to 3

    load_balancer {
        target_group_arn = var.alb_target_group_arn # Reference the target group
        container_name   = "${aws_ecs_task_definition.app_task.family}"
        container_port   = 3000 # Specify the container port
    }

    network_configuration {
        subnets          = var.private_subnets_ids
        assign_public_ip = true     # Provide the containers with public IPs
        security_groups  = ["${aws_security_group.service_security_group.id}"] # Set up the security group
    }
}