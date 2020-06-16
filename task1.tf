
provider "aws" {
  region  = "ap-south-1"
  profile = "abhiram"
}


// Generating key
resource "tls_private_key" "my_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "my-key"
  public_key = tls_private_key.my_key.public_key_openssh
}

// Generating Security group
resource "aws_security_group" "allow_tls" {
  name        = "my_security"
  description = "Allow TLS inbound traffic"
  

  ingress {
    description = "SSH PORT"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "HTTP PORT"
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
    Name = "allow_tls"
  }
}


// Creating instance 
resource "aws_instance" "my_instance" {
  ami 		= "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name 	=  aws_key_pair.generated_key.key_name
  security_groups = [ "my_security" ] 

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_key.private_key_pem
    host     = aws_instance.my_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "my instance"
  }

}

// Creating EBS volume
resource "aws_ebs_volume" "my_ebs_volume" {
  availability_zone = aws_instance.my_instance.availability_zone
  size              = 1

  tags = {
    Name = "my_ebs_volume"
  }
}

// Attaching EBS volume to the instance
resource "aws_volume_attachment" "ebs_volume_attach" {
  device_name = "/dev/sdh"
  volume_id   =  aws_ebs_volume.my_ebs_volume.id
  instance_id =  aws_instance.my_instance.id
  force_detach = true
}

// Partitioning and Mounting HD
resource "null_resource" "nullremote3"  {
depends_on = [
    aws_volume_attachment.ebs_volume_attach,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_key.private_key_pem
    host     = aws_instance.my_instance.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Sai-Abhiram/hybrid_cloud1.git /var/www/html/"
    ]
  }
}



// Create S3 bucket
resource "aws_s3_bucket" "my_bucket" {

    depends_on = [
      null_resource.nullremote3
    ]

    bucket = "my-tf-bucket-726"
    acl = "public-read"

    provisioner "local-exec" {
	command = "git clone https://github.com/Sai-Abhiram/hybrid_cloud1.git git-image"
    }

    provisioner "local-exec" {
	when = destroy
	command = "rmdir /Q /S git-image"
    }
 
    tags = {
	Name        = "my-tf-bucket-726"
	Environment = "Dev"
    }
    force_destroy = true
}


// adding github image to S3 bucket
resource "aws_s3_bucket_object" "image-bucket-object" {
  depends_on = [aws_s3_bucket.my_bucket]
  acl	= "public-read"
  bucket = aws_s3_bucket.my_bucket.bucket
  key = "index.html"
  source = "git-image/Nature-climate.jpg"


}

locals {
  s3_origin_id = "S3-aws_s3_bucket.my_bucket.bucket"
}



// Create Cloudfront distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_bucket.bucket_domain_name
    origin_id   = local.s3_origin_id
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "my git data"
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
       query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

 ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"


 restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.my_key.private_key_pem
    host     = aws_instance.my_instance.public_ip
  }

  provisioner "remote-exec"{
    inline = [
      "sudo su <<EOF",
      "echo \"<img src ='http://${self.domain_name}/${aws_s3_bucket_object.image-bucket-object.key}' width='600' height='500'>\" >> /var/www/html/index.html",
      "EOF",
      "sudo systemctl restart httpd"
     ]	

  }

  tags = {
    Environment = "production"
  }
  
}

output "CDN" {
  value = aws_cloudfront_distribution.s3_distribution
}


// Launching the site on chrome
resource "null_resource" "nulllocal1"  {


depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.my_instance.public_ip}"
  	}
	
	
}