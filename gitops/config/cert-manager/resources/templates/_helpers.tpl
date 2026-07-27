{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "cert-manager-resources.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "cert-manager-resources.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ACME registration email.
*/}}
{{- define "cert-manager-resources.email" -}}
{{- required "email is required: set global.email in gitops/global-values.yaml or override it in this app's values.yaml" .Values.global.email }}
{{- end }}

{{/*
Validate the selected ACME challenge type: dns | http.
*/}}
{{- define "cert-manager-resources.challenge" -}}
{{- $c := .Values.challenge -}}
{{- if not (or (eq $c "dns") (eq $c "http")) -}}
{{- fail "challenge must be either \"dns\" or \"http\": set it in this app's values.yaml" -}}
{{- end -}}
{{- $c -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cert-manager-resources.labels" -}}
helm.sh/chart: {{ include "cert-manager-resources.chart" . }}
app.kubernetes.io/name: {{ include "cert-manager-resources.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
