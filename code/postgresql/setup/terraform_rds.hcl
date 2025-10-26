# PostgreSQL RDS Terraform設定
# 使用方法: terraform init && terraform apply

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_db_parameter_group" "postgresql_training" {
  name        = "postgresql-training-params"
  family      = "postgres16"
  description = "PostgreSQL training parameter group"

  # パフォーマンス最適化
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"  # メモリの25%
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"  # メモリの75%
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "2097152"  # 2GB
  }

  parameter {
    name  = "work_mem"
    value = "65536"  # 64MB
  }

  # ログ設定
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # 1秒以上のクエリ
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # auto_explain
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,auto_explain"
  }

  parameter {
    name  = "auto_explain.log_min_duration"
    value = "1000"
  }
}

resource "aws_db_instance" "postgresql_training" {
  identifier     = "postgresql-training"
  engine         = "postgres"
  engine_version = "16.1"
  
  instance_class    = "db.t3.medium"
  allocated_storage = 100
  storage_type      = "gp3"
  iops              = 3000
  
  db_name  = "training_db"
  username = "training_user"
  password = var.db_password  # Variables.tfで定義
  
  parameter_group_name = aws_db_parameter_group.postgresql_training.name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
  
  publicly_accessible = false
  
  skip_final_snapshot = true
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  tags = {
    Name        = "PostgreSQL Training DB"
    Environment = "training"
  }
}

output "db_endpoint" {
  value = aws_db_instance.postgresql_training.endpoint
}
