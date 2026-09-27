# ---------------------------------------------------------------------------
# NLB in the public subnets, forwarding to worker NodePorts. Waits for
# worker bootstrap to complete so target health checks don't flap while
# kubelet/kube-proxy are still coming up.
# ---------------------------------------------------------------------------
resource "aws_lb" "app_nlb" {
  name               = "${var.cluster_name}-nlb"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.cluster_name}-nlb" }
}

# --- Frontend ------------------------------------------------------------
resource "aws_lb_target_group" "frontend" {
  name        = "${var.cluster_name}-frontend-tg"
  port        = var.frontend_nodeport
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.frontend_nodeport)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = { Name = "${var.cluster_name}-frontend-tg" }
}

resource "aws_lb_target_group_attachment" "frontend_worker" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.frontend_nodeport
  depends_on       = [null_resource.worker_bootstrap]
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.app_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# --- Backend (optional - toggle with var.expose_backend_on_nlb) ----------
resource "aws_lb_target_group" "backend" {
  count       = var.expose_backend_on_nlb ? 1 : 0
  name        = "${var.cluster_name}-backend-tg"
  port        = var.backend_nodeport
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.backend_nodeport)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = { Name = "${var.cluster_name}-backend-tg" }
}

resource "aws_lb_target_group_attachment" "backend_worker" {
  count            = var.expose_backend_on_nlb ? var.worker_count : 0
  target_group_arn = aws_lb_target_group.backend[0].arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.backend_nodeport
  depends_on       = [null_resource.worker_bootstrap]
}

resource "aws_lb_listener" "backend" {
  count             = var.expose_backend_on_nlb ? 1 : 0
  load_balancer_arn = aws_lb.app_nlb.arn
  port              = 3500
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend[0].arn
  }
}
