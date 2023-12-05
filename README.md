# Simple-Data-Migration-Using-DMS
In this project we will be assisting a company who is planning to move their data to the cloud usng AWS. Using Terraform in VS Code and AWS Cloud services, use AWS DMS to transfer the company’s on-prem data to an AWS Relational Database Service (RDS). 
Normally there would already be a source database owned by the company and we would  transfer that data to an Amazon database, but since this is fictional, we’ll create the source database and say it belongs to the company fpr this scenario. Then we'll create the target database, which will be an AWS Relational Database, to receive all the migrated data from the company. 

When we execute our Terraform code at the end, the expected process is this:
  - AWS DMS will use the replication instance to read data from the source database and write it to the target database based on the defined task and mappings.
  - The process can be monitored through the AWS Management Console.
  - Once the initial load (full-load) is completed, you can also configure change data capture (CDC) if ongoing replication is required.
