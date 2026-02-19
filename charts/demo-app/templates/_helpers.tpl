{{- define "demo-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "demo-app.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "demo-app.labels" -}}
app.kubernetes.io/name: {{ include "demo-app.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "demo-app.sparkTemplateSpec" -}}
{{- $spark := .spark -}}
{{- $image := .image -}}
type: {{ $spark.type | quote }}
mode: {{ $spark.mode | quote }}
sparkVersion: {{ $spark.sparkVersion | quote }}
pythonVersion: {{ $spark.pythonVersion | quote }}
image: "{{ required "image.repository must be set" $image.repository }}:{{ $image.tag }}"
imagePullPolicy: {{ $image.pullPolicy | quote }}
mainApplicationFile: {{ $spark.mainApplicationFile | quote }}
{{- with $spark.arguments }}
arguments:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $spark.sparkConf }}
sparkConf:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $spark.timeToLiveSeconds }}
timeToLiveSeconds: {{ . }}
{{- end }}
{{- with $spark.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end }}
restartPolicy:
  type: {{ default "Never" $spark.restartPolicy.type | quote }}
driver:
  cores: {{ $spark.driver.cores }}
  coreLimit: {{ $spark.driver.coreLimit | quote }}
  memory: {{ $spark.driver.memory | quote }}
  serviceAccount: {{ $spark.driver.serviceAccount | quote }}
{{- with $spark.driver.labels }}
  labels:
{{ toYaml . | indent 4 }}
{{- end }}
executor:
  instances: {{ $spark.executor.instances }}
  cores: {{ $spark.executor.cores }}
  coreLimit: {{ $spark.executor.coreLimit | quote }}
  memory: {{ $spark.executor.memory | quote }}
  deleteOnTermination: {{ $spark.executor.deleteOnTermination }}
{{- with $spark.executor.labels }}
  labels:
{{ toYaml . | indent 4 }}
{{- end }}
{{- end -}}
