{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "zitadel-resources.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "zitadel-resources.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified public hostname: <subdomain>.<global.domain>
*/}}
{{- define "zitadel-resources.host" -}}
{{- $domain := required "domain is required: set global.domain in gitops/global-values.yaml or override it in this app's values.yaml" .Values.global.domain -}}
{{- $sub := required "subdomain is required: set it in this app's values.yaml" .Values.subdomain -}}
{{- printf "%s.%s" $sub $domain }}
{{- end }}

{{/*
ClusterIssuer name. Per-app .Values.issuer overrides .Values.global.issuer.
*/}}
{{- define "zitadel-resources.issuer" -}}
{{- required "issuer is required: set global.issuer in gitops/global-values.yaml or override it in this app's values.yaml" (.Values.issuer | default .Values.global.issuer) }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "zitadel-resources.labels" -}}
helm.sh/chart: {{ include "zitadel-resources.chart" . }}
app.kubernetes.io/name: {{ include "zitadel-resources.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
