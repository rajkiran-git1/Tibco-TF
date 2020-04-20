terraform {
  backend "s3" {
    bucket = "nonprod-state"
    key    = "env/uat/tibco/terraform.state"
    region = "us-west-1"
  }
}
