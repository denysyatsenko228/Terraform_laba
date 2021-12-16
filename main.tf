terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  credentials = file("/home/denysyatsenko/service-account.json.json")
  project = "terraform3ta"
  region  = "europe-west1"
  zone    = "europe-west1-c"
}

resource "google_compute_network" "vpc_yatsenko" {
  name                    = "vpc-network"
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnetwork-1" {
  name                    = "yatsenko-private-1"
  ip_cidr_range           = "10.0.1.0/24"
  network                 = "vpc_yatsenko"
}

resource "google_compute_subnetwork" "subnetwork-2" {
  name                    = "yatsenko-private-2"
  ip_cidr_range           = "10.0.2.0/24"
  network                 = "vpc_yatsenko"
  private_ip_google_access = "true"
}

resource "google_compute_firewall" "firewall" {
  name          = "yatsenko-firewall"
  network       = "vpc_yatsenko"
  source_ranges = ["10.0.1.0/24", "10.0.2.0/24"]
  priority      = "65534"

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["1-65535"]
  }
  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "default-allow-icmp-three-tier" {
  name = "firewall-icmp"
  network = "vpc_yatsenko"
  priority = "65534"
    allow {
      protocol = "icmp"
    }
}

resource "google_compute_firewall" "allow-lb-health" {
  name = "lb-health-check"
  network = "vpc_yatsenko"
  priority = "65534"
  direction = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags = ["allow-healthcheck"]

    allow {
      protocol = "tcp"
      ports = ["80"]
    }
}

resource "google_compute_firewall" "allow-http" {
  name = "allow-http"
  network = "vpc_yatsenko"
  direction = "INGRESS"
  target_tags = ["allow-http"]
    allow {
      protocol = "tcp"
      ports = ["80"]
    }
}

resource "google_compute_firewall" "allow-ssh-ingress-from-iap" {
  name = "allow-ssh-ingress-from-iap"
  network = "vpc_yatsenko"
  direction = "INGRESS"
  target_tags = ["allow-ssh"]
  source_ranges = ["35.235.240.0/20"]
    allow {
      protocol = "tcp"
      ports = ["22"]
    }
}

resource "google_compute_instance_template" "backend_template" {
  name         = "backend_instance"
  machine_type = "f1-micro"

  disk {
    source_image = "debian-cloud/debian-10"
    auto_delete  = true
    boot         = true
    disk_size_gb = "10"
  }

  network_interface {
    network = "vpc_yatsenko"
    subnetwork = "subnetwork-2"
  }

  tags = ["allow-ssh", "allow-lb-health"]

  metadata_startup_script = file("start.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "backend_mig" {
  name               = "backend"
  base_instance_name = "mini-denys"
  zone               = ["europe-west1-b", "europe-west1-c"]
  target_size        = "2"
  version {
    instance_template  = google_compute_instance_template.backend_template
  }
}

resource "google_compute_autoscaler" "scaler_denys" {
  name   = "autoscaler"
  zone   = "europe-west1-b"
  target = google_compute_instance_group_manager.backend_mig

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 2
    cpu_utilization {
      target = 0.7
    }
  }
}

resource "google_compute_health_check" "tcp-health-check" {
  name = "tcp-health-check"

  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}

resource "google_compute_backend_service" "backend-bs" {
  name                  = "backend-service"
  protocol              = "tcp"
  load_balancing_scheme = "INTERNAL"
  network               = "vpc_yatsenko"
  health_checks = [google_compute_health_check.tcp-health-check.id]
}

resource "google_compute_backend_service" "add-backend-bs" {
  name = "add-instances"
  backend {
    group = google_compute_backend_service.backend-bs
  }
}

resource "google_compute_forwarding_rule" "backend-lb" {
  name = "backend-lb"
  ports = ["80"]
  backend_service = "backend-bs"
  load_balancing_scheme = "INTERNAL"
  network = "vpc_yatsenko"
  subnetwork = "subnetwork-2"
  ip_protocol = "tcp"
}

resource "google_compute_instance_template" "frontend_template" {
  name         = "frontend_instance"
  machine_type = "f1-micro"

  disk {
    source_image = "centos-cloud/centos-7"
    auto_delete  = true
    boot         = true
    disk_size_gb = "20"
  }

  network_interface {
    network = "vpc_yatsenko"
    subnetwork = "subnetwork-1"
  }

  tags = ["allow-ssh" ,"allow-healthcheck" ,"allow-http"]

  metadata_startup_script = file("startfront.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "frontend_mig" {
  name               = "frontend"
  base_instance_name = "mini-denys-2"
  zone               = ["europe-west1-b", "europe-west1-c"]
  target_size        = "2"
  named_port {
    name = "http"
    port = 80
  }
  version {
    instance_template  = google_compute_instance_template.frontend_template
  }
}

resource "google_compute_autoscaler" "scaler_denys_front" {
  name   = "autoscaler_front"
  zone   = "europe-west1-b"
  target = google_compute_instance_group_manager.frontend_mig

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 2
    cpu_utilization {
      target = 0.7
    }
  }
}

resource "google_compute_health_check" "http-check-front" {
  name = "tcp-health-check-front"

  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}

resource "google_compute_backend_service" "frontend-bs" {
  name                  = "frontend-service"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "INTERNAL"
  network               = "vpc_yatsenko"
  health_checks = [google_compute_health_check.http-check-front.id]
}

resource "google_compute_backend_service" "add-frontend-bs" {
  name = "add-frontend-bs"
  backend {
    group = "google_compute_instance_group_manager.frontend_mig"
  }
}
resource "google_compute_url_map" "urlmap" {
  name            = "urlmap"
  default_service = google_compute_backend_service.frontend-bs.id
  path_matcher {
    name            = "pathmap"
    default_service = google_compute_backend_service.frontend-bs.id
    path_rule {
      paths = ["/*=frontend-bs"]
    }
  }
}

resource "google_compute_target_https_proxy" "default" {
  name             = "proxy"
  url_map          = google_compute_url_map.urlmap
  ssl_certificates = [google_compute_target_https_proxy.default]
}








