# Terraform Workshop
Terraform is a powerful multi-cloud "Infrastructure as Code" tool that helps you provision and manage resources effectively anywhere. In this workshop, we'll introduce basic AWS concepts and write Terraform code to incrementally create AWS resources. Finally we'll deploy a simple application to the cloud and tear everything down at the end.

## Prerequisites
- An AWS account (if you don't already have one, sign up for free credits at https://aws.amazon.com/free/)
- AWS CLI installed (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)
- AWS credentials created (https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys)
- AWS credentials configured, use region=us-east-1 (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html#cli-configure-files-where) 
- Terraform CLI installed (https://learn.hashicorp.com/tutorials/terraform/install-cli)
- Optional: install [HashiCorp Terraform plugin for VSCode](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform&ssr=false#overview) for syntax highlighting and autocompletion.

## Cost
Running this workshop should not incur any cost on AWS if you haven't exceeded your Free Tier limit.

## Cheatsheet
- `terraform init`: initialize or update the setup
- `terraform fmt`: auto-indent/prettify code
- `terraform validate`: validate code
- `terraform plan`: see infrastructure changes
- `terraform apply`: apply changes (when answer `yes`)
- `terraform show`: describe current state of all resources
- `terraform destroy`: destroy everything (when answer `yes`)

## Exercises
The following is a series of exercises that should be executed in order.

### 0. The basics
- Clone this repo
  ```
  git clone https://github.com/phuongdh/terraform-workshop.git
  cd terraform-workshop
  ```

- Look at the content of `main.tf`

- Initialize the project
  ```
  terraform init
  ```

- Create resources
  ```
  terraform apply
  ```
  None were created because we haven't described any resource yet!

### 1. Create your first resource
- Create a new file named `ec2.tf`, add an [`aws_instance` resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance). There are a lot of parameters, but only `ami` and `instance_type` are required, Terraform will fill in the rest.
  ```
  resource "aws_instance" "demo" {
    ami           = "ami-0be2609ba883822ec"
    instance_type = "t2.micro"
  }
  ```

- Validate the templates
  ```
  terraform validate
  ```

- Check what will change, there's a lot
  ```
  terraform plan
  ```

- Apply the change
  ```
  terraform apply
  ```
  At this point, if you encounter an error about missing subnet, then you don't have a default subnet. Add a `subnet-id` param to your `aws-instance`

- Check the [AWS web console](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:) to see the instance being created (remember to choose N. Virginia).

- View the Terraform state by opening `terraform.tfstate` file or run
  ```
  terraform state list
  terraform state show <resource name>
  ```

### 2. Make changes
- Our instance doesn't have a name! Add the following to `aws_instance` block in `ec2.tf`
  ```
  tags = {
    Name = "StatewideIT-demo"
  }
  ```

- Apply the change
  ```
  terraform apply
  ```
  This non-destructive change should modify the instance in-place.

- What about destructive change? Let's install LAMP stack on our instance. First add an install script `install_lamp.sh`
  ```
  #!/bin/bash
  yum update -y
  amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
  yum install -y httpd mariadb-server
  systemctl start httpd
  systemctl enable httpd
  usermod -a -G apache ec2-user
  chown -R ec2-user:apache /var/www
  chmod 2775 /var/www
  find /var/www -type d -exec chmod 2775 {} \;
  find /var/www -type f -exec chmod 0664 {} \;
  echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
  ```
  This script will install PHP, MariaDB, and Apache web server. It also creates a sample php page.

- Then add the following to `aws_instance` block in `ec2.tf` 
  ```
  user_data = file("install_lamp.sh")
  ```
  `user_data` is instruction that runs when the EC2 is created. This uses HCL's `file` function to read and assign file content to `user_data`.

- Apply the change
  ```
  terraform apply
  ```
  Look at the web console, your instance should be replaced. Side note: you can also grab an AMI with the LAMP stack preinstalled from the Marketplace.

- Copy the instance's public IP from the web console or by running
  ```
  terraform show | grep public_ip
  ```
  
- In your browser, navigate to the copied IP address. It doesn't work! That's because its security group doesn't allow incoming connections.

### 3. Expose ports
- What is [security group](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)?

- Add a naive security group
  ```
  resource "aws_security_group" "allow_http" {
    name        = "allow_http"
    description = "Allow HTTP inbound traffic"

    ingress {
      from_port   = 80
      to_port     = 80
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
      Name = "allow_http"
    }
  }
  ```
  Warning: this opens your instance to the world, not recommended outside of demo purposes.

- Attach the security group to your EC2 instance
  ```
  resource "aws_instance" "demo" {
    ...
    security_groups = [ aws_security_group.allow_http.name ]
  }
  ```

- We're going to need the public IP address again, let's make it easier by adding this output block
  ```
  output "public_ip" {
    value = aws_instance.demo.public_ip
  }
  ```

- Apply the change
  ```
  terraform apply
  ```
  Your EC2 instance will be replaced.

- Find the public IP address in the output and navigate to it. You should see a WordPress page.


### 4. Use variables
Wouldn't it be nice if users can easily change instance's size or name without digging into our code?

- Create `variables.tf`
  ```
  variable "instance_type" {
    default = "t2.micro"
  }

  variable "instance_name" {
    default = "StatewideIT-demo"
  }
  ```

- Modify `ec2.tf`
  ```
  resource "aws_instance" "demo" {
    ...
    instance_type = var.instance_type
    tags = {
      Name = var.instance_name
    }
  }
  ```

- Change the name inline
  ```
  terraform apply -var 'instance_name=NewName'
  ```

- Or create a `demo.tfvars` file
  ```
  instance_name = "StatewideIT-demo"
  ```
  then apply
  ```
  terraform apply -var-file="demo.tfvars"
  ```

### 5. Use remote state
So far only you have the state file on your local machine, that's risky and not collaborative. You don't want to commit it to your repo either. Let's store it in S3.
- Create an S3 bucket (name must be unique)
- Modify `main.tf`
  ```
  terraform {
    ...
    backend "s3" {
      bucket = "<your bucket name>"
      key    = "terraform.tfstate"
      region = "us-east-1"       
    }
  }
  ```
- Migrate the backend from local to S3
  ```
  terraform init
  ```

- View the state file in your S3 bucket

- Double check that nothing has changed
  ```
  terraform plan
  ```

### 6. Tear down
- Delete resources
  ```
  terraform destroy
  ```

- Delete your S3 bucket
