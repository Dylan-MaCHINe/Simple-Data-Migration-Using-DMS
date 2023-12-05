# first define our provider, region, and credential information
provider "aws" {
  region                   = "us-east-1"
  shared_credentials_files = ["~/.aws/credentials"]
}

# second we'll create two Relational Databases:
#   - first one is for the source database that is on-prem with the data comapny
#   - the second is for the target database where we'll be transferring the data to
resource "aws_db_instance" "source_db" {
  allocated_storage    = 20            # we are allocating 20 GB of storage
  storage_type         = "gp2"         # this is just the type of storage chosen which is good for a balanced performance
  engine               = "mysql"       # this specifies the type of engine, so in our case we chose mySQL
  engine_version       = "5.7"         # version of the engine being used
  instance_class       = "db.t2.micro" # These attributes define the hardware and engine specs of the RDS instance.
  username             = "source-username"
  password             = "source-password"
  parameter_group_name = "default.mysql.5.7"
  publicly_accessible  = true
}

# the layout of the target_db is similar to the source_db above
resource "aws_db_instance" "target_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "target-user"
  password             = "target-password"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}

# we'll also need to create a VPC for our AWS RDS to isolate and protect our database, and so that our target and source databases
# can communicate securely
resource "aws_vpc" "dms_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # this attribute enables DNS resolution 
  enable_dns_support   = true # this attribute enables hostname support within the VPC
}

# following the creation of our VPC will be our security group which will allow/deny access to our DMS replication instance
resource "aws_security_group" "dms_sg" {
  name        = "dms_security_group"
  description = "security group for our dms replication instance"
  vpc_id      = aws_vpc.dms_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dms_sg"
  }
}

# the next step is to set up the Data Migration Service (DMS) components
# for this step the first thing we'll create is the replication instance which will be performing the actual data migration
resource "aws_dms_replication_instance" "dms_replication_instance" {
  allocated_storage          = 20 # once again this determines the amount of storage to allocate in GB
  replication_instance_class = "dms.t2.micro"
  replication_instance_id    = "my_dms_replication_instance"  # this is what our dms replication instance will be known as
  apply_immediately          = true                           # just means we want the changes applied right now as opposed to later
  publicly_accessible        = false                          # for security purposes, this is false and not wanted to be available publicly
  auto_minor_version_upgrade = true                           # allows AWS to automatically apply upgrades to various resources like RDS or EC2 
  vpc_security_group_ids     = [aws_security_group.dms_sg.id] # this attribute attaches the security group we just created to this instance
  tags = {
    Name = "my-dms-replication-instance"
  }
}

# after that we'll define our source and target endpoints
# the source endpoint is the on-prem MySQL DB
# the target endpoint is the RDS MySQL DB in AWS
resource "aws_dms_endpoint" "source_endpoint" {
  endpoint_id   = "source-endpoint"    # this is what our endpoint will be known as
  endpoint_type = "source"             # since this is the source endpoint, we select "source" as the type
  engine_name   = "mysql"              # this is the database engine type
  username      = "source_db_user"     # ------
  password      = "source_db_password" # |from "username" down to "database name"  
  server_name   = "source.db.address"  # |are credentials and connection
  port          = 3306                 # |info for the database
  database_name = "sourcedb"           # ------
  ssl_mode      = "none"               # SSL refers to secure communication, however, we are selecting no SSL
  # if we did want to enable SSL for secure communication, we would select "require" 
}

# now we'll do that target endpoint
resource "aws_dms_endpoint" "target_endpoint" { # the attributes are similar to the source_endpoint above
  endpoint_id   = "target endpoint"
  endpoint_type = "target"
  engine_name   = "mysql"
  username      = "aws_db_instance.target_db.username"
  password      = "aws_db_instance.target_db.password"
  server_name   = "aws_db_instance.target_db.address"
  port          = "aws_db_instance.target_db.port"
  database_name = "aws_db_instance.target_db.name"
  ssl_mode      = "require"
}

# the next task to do is make the replication task
resource "aws_dms_replication_task" "dms_replication_task" {
  replication_task_id      = "my_dms_replication_task"
  source_endpoint_arn      = "aws_dms_endpoint.source_endpoint.arn" # we get the arn from the source_endpoint created earlier
  target_endpoint_arn      = "aws_dms_endpoint.target_endpoint.arn" # we get the arn from the target_endpoint created above
  replication_instance_arn = "aws_dms_replication_instance.dms_replication_instance.arn"
  migration_type           = "full-load" # this means we are a one-time migration of ALL the data
  table_mappings = jsondecode({          # Defines which schemas and tables to include or exclude in the migration.
    "rules" : [                          # In this case, all tables are included
      {
        "rule type" : "selection",
        "rule-id" : "1",
        "rule name" : "1",
        "object-locator" : {
          "schema-name" : "%",
          "table-name" : "%"
        },
        "rule-action" : "include"
      }
    ]
  })
}

# after that, we need to create 2 highly available subnets within our VPC and then assign our replicatiin and database instances
# to these subnets so that our replication instance and database instances can communicate with each other and if one goes down,
# then the other subnet will still be available
resource "aws_subnet" "dms_subnet1" {
  vpc_id            = aws_vpc.dms_vpc.id # the ID of the VPC we created earlier
  cidr_block        = "10.0.1.0/24"      # subnet for our first availability zone
  availability_zone = "us-east-1a"       # first availability zone
  tags = {
    Name = "dms_subnet1"
  }
}
resource "aws_subnet" "dms_subnet2" {
  vpc_id            = aws_vpc.dms_vpc.id # the ID of the VPC we created earlier
  cidr_block        = "10.0.2.0/24"      # subnet for our first availability zone
  availability_zone = "us-east-1b"       # second availability zone
  tags = {
    Name = "dms_subnet2"
  }
}

# next we'll group our db instances (target_db and source_db) together in a db subnet group
resource "aws_db_subnet_group" "dms_db_subnet_group" {
  name       = "dms_db_subnet_group"
  subnet_ids = [aws_subnet.dms_subnet1.id, aws_subnet.dms_subnet2.id]
  tags = {
    Name = "dms_db_subnet_group"
  }
}

# then for DMS to be able to talk to the source database (the company's database or "source_db") and target databse
# ("target_db") for the data migration process, we need to create an internet gateway allowing internet access to our VPC
resource "aws_internet_gateway" "dms_igw" {
  vpc_id = aws_vpc.dms_vpc.id
  tags = {
    Name = "dms_igw"
  }
}

# following the creation of our internet gateway is the route table which will route traffic to and from our VPC
resource "aws_route_table" "dms_rt" {
  vpc_id = aws_vpc.dms_vpc.id

  route {
    cidr_block = "0.0.0.0/0"                     # we are creating a default route that will route ALL traffic through our internet gateway
    gateway_id = aws_internet_gateway.dms_igw.id # this is the ID of our internet gateway we just created
  }
  tags = {
    Name = "dms_rt"
  }
}

# now that we've created our route table and subnets, we need to associate these 2 resources together
# we'll be creating 2 of these route table association resources
resource "aws_route_table_association" "dms_rt1a" {

}

# once this is all completed, we initialize our Terraform project in the terminal using the command:
#   -  terraform init
# then to execute our terraform code, we do:
#   - terraform apply
