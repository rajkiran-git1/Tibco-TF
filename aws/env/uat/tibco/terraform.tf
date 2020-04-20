terraform {
  backend "s3" {
    bucket = "nonprod-state"
    key    = "env/uat/ecp/terraform.state"
    region = "us-west-1"
  }
}
