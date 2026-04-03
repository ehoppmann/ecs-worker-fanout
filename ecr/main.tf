resource "aws_ecr_repository" "ecr-repo" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  tags                 = var.tags

  image_scanning_configuration {
    scan_on_push = true
  }
}
