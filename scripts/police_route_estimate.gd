class_name PoliceRouteEstimate
extends RefCounted

## Converts the existing native GPS route response into police dispatch cost input.
##
## Dependencies:
## - Consumes the public GPS response contract only.
## - Does not own routing, graph data, TCP/process lifecycle, dispatch policy, or presentation.


static func from_gps_response(response: Dictionary) -> Dictionary:
	if not bool(response.get("success", false)):
		return {"success": false}
	var distance_m := float(response.get("distance_m", -1.0))
	var travel_time_s := float(response.get("travel_time_s", -1.0))
	if not is_finite(distance_m) or not is_finite(travel_time_s):
		return {"success": false}
	if distance_m < 0.0 or travel_time_s < 0.0:
		return {"success": false}
	return {
		"success": true,
		"distance_m": distance_m,
		"travel_time_s": travel_time_s,
	}
