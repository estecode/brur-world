extends RefCounted
class_name GeoDotHlodResidency
const ABSENT:=0; const LOADING:=1; const READY:=2; const VISIBLE:=3; const WARM:=4
var _regions:Dictionary={}; var _tick:=0
func register_base(id:String,lod:int=0,memory_bytes:int=0)->void:
 var r:=_region(id); r.representations[lod]={"state":VISIBLE,"memory_bytes":maxi(0,memory_bytes),"last_used":_next_tick()}; r.visible_lod=lod; r.desired_lod=maxi(lod,int(r.desired_lod)); _regions[id]=r
func request(id:String,lod:int)->void:
 var r:=_region(id); r.desired_lod=maxi(lod,int(r.desired_lod)); var reps:Dictionary=r.representations
 if not reps.has(lod): reps[lod]={"state":LOADING,"memory_bytes":0,"last_used":_next_tick()}
 elif int(reps[lod].state)==ABSENT: reps[lod].state=LOADING
 _regions[id]=r
func mark_ready(id:String,lod:int,memory_bytes:int=0)->void:
 var r:=_region(id); var rep:Dictionary=r.representations.get(lod,{}); rep.state=READY; rep.memory_bytes=maxi(0,memory_bytes); rep.last_used=_next_tick(); r.representations[lod]=rep; _regions[id]=r; _commit(id)
func mark_failed(id:String,lod:int)->void:
 var r:=_region(id); if r.representations.has(lod) and int(r.representations[lod].state)==LOADING: r.representations.erase(lod); _regions[id]=r
func set_desired_lod(id:String,lod:int)->void:
 var r:=_region(id); r.desired_lod=maxi(0,lod); _regions[id]=r; _commit(id)
func visible_lod(id:String)->int:return int(_region(id).visible_lod)
func has_coverage(id:String)->bool:
 var r:=_region(id); var v:=int(r.visible_lod); return v>=0 and r.representations.has(v) and int(r.representations[v].state)==VISIBLE
func coverage_holes(ids:Array[String])->int:
 var n:=0
 for id in ids:
  if not has_coverage(id): n+=1
 return n
func duplicate_visible_owners(id:String)->int:
 var n:=0
 for rep in _region(id).representations.values():
  if int((rep as Dictionary).get("state",ABSENT))==VISIBLE:n+=1
 return maxi(0,n-1)
func resident_bytes()->int:
 var n:=0
 for rv in _regions.values():
  for rep in (rv as Dictionary).representations.values():
   if int((rep as Dictionary).get("state",ABSENT))>=READY:n+=int((rep as Dictionary).get("memory_bytes",0))
 return n
func evict_warm_to_budget(hard:int)->int:
 var ev:=0
 while resident_bytes()>maxi(0,hard):
  var cr:=""; var cl:=-1; var oldest:=9223372036854775807
  for rid in _regions.keys():
   for lk in (_regions[rid] as Dictionary).representations.keys():
    var rep:Dictionary=(_regions[rid] as Dictionary).representations[lk]
    if int(rep.state)==WARM and (cl<0 or int(rep.last_used)<oldest):cr=String(rid);cl=int(lk);oldest=int(rep.last_used)
  if cl<0:break
  var r:Dictionary=_regions[cr];r.representations.erase(cl);_regions[cr]=r;ev+=1
 return ev
func snapshot()->Dictionary:
 var holes:=0;var dup:=0
 for id in _regions.keys():
  if not has_coverage(String(id)):holes+=1
  dup+=duplicate_visible_owners(String(id))
 return {"regions":_regions.size(),"coverage_holes":holes,"duplicate_visible_owners":dup,"resident_bytes":resident_bytes()}
func _commit(id:String)->void:
 var r:=_region(id);var reps:Dictionary=r.representations;var desired:=int(r.desired_lod);var current:=int(r.visible_lod);var best:=-1
 for lk in reps.keys():
  var lod:=int(lk);var state:=int(reps[lk].state)
  # READY, VISIBLE and WARM are all resident and immediately reusable.
  if lod<=desired and state>=READY and (best<0 or lod>best):best=lod
 if best<0 or best==current:return
 if current>=0 and reps.has(current):var old:Dictionary=reps[current];old.state=WARM;old.last_used=_next_tick();reps[current]=old
 var nxt:Dictionary=reps[best];nxt.state=VISIBLE;nxt.last_used=_next_tick();reps[best]=nxt;r.visible_lod=best;_regions[id]=r
func _region(id:String)->Dictionary:
 if _regions.has(id):return (_regions[id] as Dictionary).duplicate(true)
 return {"desired_lod":0,"visible_lod":-1,"representations":{}}
func _next_tick()->int:_tick+=1;return _tick
