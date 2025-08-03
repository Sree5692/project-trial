provider "aws" {
  region  = "us-east-1"
  profile = "slr"
}


resource "aws_instance" "ec2" {
  ami           = "ami-020cba7c55df1f615" # Ubuntu 24.04 LTS
  instance_type = "t2.large"
  key_name      = "allkey.pem"

  user_data = file("${path.module}/install.sh") # << Calling the external script

  tags = {
    Name = "UbuntuEC2-trial"
  }
}
