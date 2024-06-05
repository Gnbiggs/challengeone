# challengeone

Create and configure an AWS environment for hosting a wordpress web server.

The provider is specified as region eu-west-2.

One VPC and 2 subnets are then created as the Load Balancer requires mulitple AZs.

Internet gateway created to allow internet access.

Route table created for VPC routing to the internet gateway.

Security groups created for the web server and load balancer to allow traffic via HTTP/HTTPS.

Target group attached to the application load balancer with a listener for HTTP traffic.

Credentials.json file is decoded as JSON to be able read the variables stored within the file.

Database credentials are stored within the parameter store and are created from the credentials.json file.

IAM role created for autoscaling.

Policy then attached to the IAM role.

RDS MySQL database is created within the same VPC and subnet.

Auto scaling group created for the RDS.

EC2 webserver us created with an Ubuntu AMI, using user data to install Apache, php and wordpress during bootstrap.

The instance has a lifecycle created as a redundancy options, this will create a new instance before the old one is destroyed during updates.

EC2 instances is registered with the ALB.