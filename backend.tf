terraform {
  backend "s3" {
    bucket         = "mf-jenkins-poc-tfstate"
    key            = "terraform/state.tfstate"
    region         = "us-east-1"
    use_lockfile        = true
  }
}
