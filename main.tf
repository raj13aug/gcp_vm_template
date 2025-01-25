locals {
  all_project_services = concat(var.gcp_service_list, [
    "storage.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",

  ])
}

resource "google_project_service" "enabled_apis" {
  project                    = var.project_id
  for_each                   = toset(local.all_project_services)
  service                    = each.key
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "time_sleep" "wait_project_init" {
  create_duration = "90s"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_compute_instance_template" "foobar" {
  name         = "test-app-lb-group1-mig"
  machine_type = "e2-micro"
  tags         = ["allow-health-check"]

  disk {
    source_image = data.google_compute_image.ubuntu.self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    startup-script = local.startup_script_content
  }
  depends_on = [time_sleep.wait_project_init]
}

locals {
  startup_script_path    = "startup-script.sh"
  startup_script_content = file(local.startup_script_path)
}


data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_instance_group_manager" "default" {
  name               = "instance-group"
  base_instance_name = "instance"
  version {
    instance_template = google_compute_instance_template.foobar.self_link
  }
  target_size = 1

  named_port {
    name = "http"
    port = 80
  }
  depends_on = [time_sleep.wait_project_init]
}

resource "google_compute_autoscaler" "default" {
  name   = "instance-group-autoscaler"
  target = google_compute_instance_group_manager.default.self_link
  autoscaling_policy {
    max_replicas    = 1
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.5
    }
  }
  depends_on = [time_sleep.wait_project_init]
}


resource "google_compute_http_health_check" "default" {
  name               = "http-health-check"
  check_interval_sec = 10
  timeout_sec        = 5
  request_path       = "/"
  depends_on         = [time_sleep.wait_project_init]
}

resource "google_compute_backend_service" "default" {
  name          = "http-backend-service"
  protocol      = "HTTP"
  port_name     = "http"
  health_checks = [google_compute_http_health_check.default.self_link]

  backend {
    group = google_compute_instance_group_manager.default.instance_group
  }
  depends_on = [time_sleep.wait_project_init]
}

resource "google_compute_url_map" "default" {
  name            = "url-map"
  default_service = google_compute_backend_service.default.self_link
  depends_on      = [time_sleep.wait_project_init]
}

resource "google_compute_target_http_proxy" "default" {
  name       = "http-proxy"
  url_map    = google_compute_url_map.default.self_link
  depends_on = [time_sleep.wait_project_init]
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "http-forwarding-rule"
  target                = google_compute_target_http_proxy.default.self_link
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
  depends_on            = [time_sleep.wait_project_init]
}

resource "google_compute_firewall" "allow-http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-health-check"]
  depends_on    = [time_sleep.wait_project_init]
}