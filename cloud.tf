provider "aws" {
   region = "ap-south-1"
   profile = "raja"
}

resource "aws_security_group" "mygroup" {
  name        = "mslizard111"
  description = "Allow ssh and http"
  vpc_id      = "vpc-a8766ac0"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
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
    Name = "securitygp"
  }
}



 resource "aws_instance"  "web" {
     ami           =  "ami-0385d44018fb771b7"
     instance_type = "t2.micro"
     key_name  = "cloudkey"
     security_groups = [ "mslizard111" ]

    connection {
       type = "ssh"
       user = "ec2-user"
       private_key = file("C:/Users/Dell/Downloads/cloudkey.pem")
       host = aws_instance.web.public_ip
      }



     provisioner "remote-exec"  {
       inline = [
        "sudo yum install httpd php git  -y" ,
        "sudo systemctl restart httpd",
        "sudo systemctl enable httpd"
           ]
        }

    tags = {
      Name  =  "Task-1"
     }

depends_on = [
 aws_security_group.mygroup,
  ]
}


resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1

  tags = {
    Name = "Volume_persistent"
    }
}


resource "aws_volume_attachment"  "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.web.id
  force_detach = true
 
 depends_on = [
     aws_ebs_volume.ebs1,
  ]  
}


output "my_os_IP" {
      value = aws_instance.web.public_ip

}


resource "null_resource" "nulllocal" {
    provisioner "local-exec" {
        command = "echo ${aws_instance.web.public_ip} > publicip.txt"
   }


}


resource "null_resource" "nullresource1" {
    depends_on = [
         aws_volume_attachment.ebs_att,
   ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Dell/Downloads/cloudkey.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Ds123-wq/terrafor_launch_ec2.git /var/www/html/"
    ]
  }
}




resource "aws_s3_bucket" "s3-bucket" {
  bucket = "my-123bucket"
  force_destroy = true
  acl    = "public-read"
  
depends_on = [
 aws_volume_attachment.ebs_att,
]
}

resource "null_resource" "nulllocal23"{
provisioner "local-exec" {
       
        command     = "git clone https://github.com/Ds123-wq/terrafor_launch_ec2.git Images"
     
    }
provisioner "local-exec" {
        when        =   destroy
        command     =   "rmdir /s /q Images"
    }
 depends_on = [
  aws_s3_bucket.s3-bucket
  ]
}


resource "aws_s3_bucket_object" "image-upload" {
    bucket  = aws_s3_bucket.s3-bucket.bucket
    content_type = "image/png"
    key     = "apache-web-server.png"
    source  = "Images/apache-web-server.png"
    acl     = "public-read"

depends_on = [
   null_resource.nulllocal23,
 ]
}

locals {
  s3_origin_id = "S3-${aws_s3_bucket.s3-bucket.bucket}"
}


output "s3information" {
 value = aws_s3_bucket.s3-bucket
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "my-OAI"

depends_on = [
  aws_s3_bucket_object.image-upload,
 ]
}



resource "aws_cloudfront_distribution" "s3_distribution" {

  origin {
    domain_name = aws_s3_bucket.s3-bucket.bucket_regional_domain_name
    origin_id  = local.s3_origin_id
   
  custom_origin_config {

         http_port = 80
         https_port = 80
         origin_protocol_policy = "match-viewer"
         origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"] 
        }
    
  }

   enabled             = true

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

   

restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }

viewer_certificate {
        cloudfront_default_certificate = true
    }

connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.web.public_ip
        port    = 22
        private_key = file("C:/Users/DELL/Downloads/cloudkey.pem")
    }

provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
             "echo \"<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-upload.key}' width = '300' height = '200'>\" >> /var/www/html/index.html",
            "EOF"
        ]

   }

depends_on = [
   aws_s3_bucket_object.image-upload,
  ]

provisioner "local-exec" {
  command = "chrome ${aws_instance.web.public_ip}"

}
}
