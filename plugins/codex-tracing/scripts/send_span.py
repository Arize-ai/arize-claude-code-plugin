#!/usr/bin/env python3
"""
Send OTLP spans to Arize AX via gRPC.
Phoenix uses REST API directly from bash.
"""

import base64
import json
import os
import sys


def any_value_from_json(common_pb2, value):
    if not isinstance(value, dict):
        return common_pb2.AnyValue(string_value=str(value))
    if "stringValue" in value:
        return common_pb2.AnyValue(string_value=str(value["stringValue"]))
    if "intValue" in value:
        try:
            return common_pb2.AnyValue(int_value=int(value["intValue"]))
        except (TypeError, ValueError):
            pass
    if "doubleValue" in value:
        try:
            return common_pb2.AnyValue(double_value=float(value["doubleValue"]))
        except (TypeError, ValueError):
            pass
    if "boolValue" in value:
        raw = value["boolValue"]
        if isinstance(raw, str):
            raw = raw.strip().lower() in ("true", "1", "yes")
        return common_pb2.AnyValue(bool_value=bool(raw))
    if "bytesValue" in value:
        raw = value["bytesValue"]
        try:
            data = base64.b64decode(raw)
        except Exception:
            data = str(raw).encode("utf-8", errors="ignore")
        return common_pb2.AnyValue(bytes_value=data)
    if "arrayValue" in value:
        return common_pb2.AnyValue(string_value=json.dumps(value.get("arrayValue", {}).get("values", [])))
    if "kvlistValue" in value:
        return common_pb2.AnyValue(string_value=json.dumps(value.get("kvlistValue", {}).get("values", [])))
    return common_pb2.AnyValue(string_value=json.dumps(value))


def send_to_arize_grpc(span_data: dict, api_key: str, space_id: str) -> bool:
    try:
        import grpc
        from opentelemetry.proto.collector.trace.v1 import trace_service_pb2
        from opentelemetry.proto.collector.trace.v1 import trace_service_pb2_grpc
        from opentelemetry.proto.trace.v1 import trace_pb2
        from opentelemetry.proto.common.v1 import common_pb2
        from opentelemetry.proto.resource.v1 import resource_pb2

        project_name = os.environ.get("ARIZE_PROJECT_NAME", "codex")
        endpoint = os.environ.get("ARIZE_OTLP_ENDPOINT", "otlp.arize.com:443")
        try:
            status_ok = trace_pb2.Status.StatusCode.STATUS_CODE_OK
        except AttributeError:
            status_ok = getattr(trace_pb2.Status, "STATUS_CODE_OK", 1)

        resource_spans = []
        for rs in span_data.get("resourceSpans", []):
            resource_attrs = [
                common_pb2.KeyValue(
                    key="arize.project.name",
                    value=common_pb2.AnyValue(string_value=project_name),
                )
            ]
            for attr in rs.get("resource", {}).get("attributes", []):
                key = attr.get("key", "")
                if not key:
                    continue
                resource_attrs.append(
                    common_pb2.KeyValue(
                        key=key,
                        value=any_value_from_json(common_pb2, attr.get("value", {})),
                    )
                )
            resource = resource_pb2.Resource(attributes=resource_attrs)

            scope_spans = []
            for ss in rs.get("scopeSpans", []):
                spans = []
                for s in ss.get("spans", []):
                    attrs = [
                        common_pb2.KeyValue(
                            key="arize.project.name",
                            value=common_pb2.AnyValue(string_value=project_name),
                        )
                    ]
                    for attr in s.get("attributes", []):
                        key = attr.get("key", "")
                        if not key:
                            continue
                        attrs.append(
                            common_pb2.KeyValue(
                                key=key,
                                value=any_value_from_json(common_pb2, attr.get("value", {})),
                            )
                        )

                    try:
                        kind_value = int(s.get("kind", 1))
                    except (TypeError, ValueError):
                        kind_value = 1

                    span = trace_pb2.Span(
                        trace_id=bytes.fromhex(s.get("traceId", "0" * 32)),
                        span_id=bytes.fromhex(s.get("spanId", "0" * 16)),
                        parent_span_id=bytes.fromhex(s.get("parentSpanId", "")) if s.get("parentSpanId") else b"",
                        name=s.get("name", "span"),
                        kind=kind_value,
                        start_time_unix_nano=int(s.get("startTimeUnixNano", 0)),
                        end_time_unix_nano=int(s.get("endTimeUnixNano", 0)),
                        attributes=attrs,
                        status=trace_pb2.Status(code=status_ok),
                    )
                    spans.append(span)

                scope_info = ss.get("scope", {}) or {}
                scope_kwargs = {}
                if scope_info.get("name"):
                    scope_kwargs["name"] = scope_info["name"]
                if scope_info.get("version"):
                    scope_kwargs["version"] = scope_info["version"]
                scope_args = {"spans": spans}
                if scope_kwargs:
                    scope_args["scope"] = common_pb2.InstrumentationScope(**scope_kwargs)
                scope_spans.append(trace_pb2.ScopeSpans(**scope_args))

            resource_spans.append(trace_pb2.ResourceSpans(resource=resource, scope_spans=scope_spans))

        request = trace_service_pb2.ExportTraceServiceRequest(resource_spans=resource_spans)
        credentials = grpc.ssl_channel_credentials()
        channel = grpc.secure_channel(endpoint, credentials)
        stub = trace_service_pb2_grpc.TraceServiceStub(channel)
        metadata = [("authorization", f"Bearer {api_key}"), ("space_id", space_id)]
        stub.Export(request, metadata=metadata, timeout=10)
        channel.close()
        return True
    except Exception as exc:
        print(f"[arize] gRPC error: {exc}", file=sys.stderr)
        return False


def main() -> None:
    try:
        span_data = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"[arize] Invalid JSON: {exc}", file=sys.stderr)
        sys.exit(1)

    api_key = os.environ.get("ARIZE_API_KEY")
    space_id = os.environ.get("ARIZE_SPACE_ID")
    if not api_key or not space_id:
        print("[arize] ARIZE_API_KEY and ARIZE_SPACE_ID required", file=sys.stderr)
        sys.exit(1)

    ok = send_to_arize_grpc(span_data, api_key, space_id)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
