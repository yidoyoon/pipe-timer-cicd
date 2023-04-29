# RDS(MySQL)
output "mysql_host" {
  value = aws_db_instance.mysql.address
}

# Elasticache(Redis)
output "redis_url" {
  value = aws_elasticache_cluster.redis.cache_nodes
}
