# terraform/modules/redis/outputs.tf

output "endpoint" {
  value = aws_elasticache_cluster.main.cache_nodes[0].address
  # Example: hospital-devops-redis.abc123.cfg.use1.cache.amazonaws.com
}

output "port" {
  value = aws_elasticache_cluster.main.port
}
