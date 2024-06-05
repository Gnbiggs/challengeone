# challengeone

Create and configure an AWS environment for hosting a wordpress web server.

The provider is specified as region eu-west-2.

One VPC and Subnet configured (Main), for best practises there would be 2 configured using multiple AZ's.

Internet gateway created to allow internet access.

Route table created for VPC routing to the internet gateway.

Security groups created for the web server and load balancer to allow traffic via HTTP/HTTPS.

Target group attached to the application load balancer with a listener for HTTP traffic.

Database credentials are stored within the parameter store and are created from the credentials.cf file.

RDS MySQL database is created within the same VPC and subnet.

EC2 webserver us created with an Ubuntu AMI, using user data to install Apache, php and wordpress during bootstrap.

The instance has a lifecycle created as a redundancy options, this will create a new instance before the old one is destroyed during updates.

EC2 instances is registered with the ALB.