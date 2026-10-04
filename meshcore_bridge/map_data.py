"""Public advertised positions only; no location guessing or remote queries."""
import math

def nodes(radio):
    result=[]
    for key,c in radio.contacts.items():
        lat,lon=c.get('adv_lat'),c.get('adv_lon')
        valid=all(isinstance(v,(int,float)) and math.isfinite(v) for v in (lat,lon))
        valid=valid and -90<=lat<=90 and -180<=lon<=180 and (lat!=0 or lon!=0)
        result.append(dict(id='dm:'+key,name=c.get('adv_name',key[:12]),type=c.get('type',0),latitude=lat if valid else None,longitude=lon if valid else None,last_advert=c.get('last_advert',0)))
    return result
