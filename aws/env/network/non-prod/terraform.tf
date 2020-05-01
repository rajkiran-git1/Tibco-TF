terraform {
  backend "s3" {
    bucket = "nonprod-state"
    key    = "env/network/nonprod/terraform.state"
    region = "us-west-1"
  }
}
