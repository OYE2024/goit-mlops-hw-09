output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = helm_release.argocd.namespace
}

output "argocd_server_service" {
  description = "ArgoCD server service name"
  value       = "argocd-server"
}

output "port_forward_command" {
  description = "Command to port-forward ArgoCD UI"
  value       = "kubectl port-forward -n ${helm_release.argocd.namespace} svc/argocd-server 8080:443"
}

output "get_admin_password_command" {
  description = "Command to retrieve ArgoCD admin password"
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
