# EC2
output "backend_public_ip" {
  value = aws_instance.pipe-timer-backend.public_ip
}

# RDS(MySQL)
output "mysql_host" {
  value = aws_db_instance.mysql.address
}

# Elasticache(Redis)
output "redis_url" {
  value = aws_elasticache_cluster.redis.cache_nodes
}

# VPC
output "vpc_id" {
  value = module.staging_vpc.vpc_id
}

# Subnet 1
output "subnet_1" {
  value = module.staging_vpc.public_subnet_1_id
}
