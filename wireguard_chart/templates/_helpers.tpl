{{- define "wireguard.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "wireguard.labels" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "wireguard.selectorLabels" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "wireguard.serviceAccountName" -}}
{{- if .Values.rbac.create }}
{{- .Values.rbac.serviceAccountName }}
{{- else }}
default
{{- end }}
{{- end }}

{{/*
Prefijo de la red WireGuard (extrae el /24 de networkCIDR)
*/}}
{{- define "wireguard.networkPrefix" -}}
{{- index (splitList "/" .Values.wireguard.networkCIDR) 1 }}
{{- end }}
