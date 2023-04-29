# EC2
output "backend_public_ip" {
  value = aws_instance.pipe-timer-backend.public_ip
}
