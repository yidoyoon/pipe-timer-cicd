# EC2
output "frontend_public_ip" {
  value = aws_instance.pipe-timer-frontend.public_ip
}
