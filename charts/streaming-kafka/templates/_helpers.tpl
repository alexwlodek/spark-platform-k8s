{{- define "streaming-kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "streaming-kafka.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "streaming-kafka.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "streaming-kafka.labels" -}}
app.kubernetes.io/name: {{ include "streaming-kafka.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "streaming-kafka.bootstrapHost" -}}
{{ include "streaming-kafka.fullname" . }}.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "streaming-kafka.controllerHost" -}}
{{ include "streaming-kafka.fullname" . }}-0.{{ include "streaming-kafka.fullname" . }}-headless.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}
