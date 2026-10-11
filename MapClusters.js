.pragma library

// Group projected positions, so density follows zoom rather than geographic distance.
function build(points, zoom) {
    const groups = []
    const radius = zoom < 10 ? 60 : zoom < 13 ? 52 : 45
    points.slice().sort((a,b) => a.node.id.localeCompare(b.node.id)).forEach(function(p) {
        let group = null
        let best = radius * radius
        for (const g of groups) {
            const distance = (g.x-p.x)*(g.x-p.x)+(g.y-p.y)*(g.y-p.y)
            if (distance < best) { group = g; best = distance }
        }
        if (!group) groups.push({x:p.x,y:p.y,members:[p.node],latitude:p.node.latitude,longitude:p.node.longitude,label:false})
        else {
            const count = group.members.length
            group.x=(group.x*count+p.x)/(count+1); group.y=(group.y*count+p.y)/(count+1)
            group.latitude=(group.latitude*count+p.node.latitude)/(count+1)
            group.longitude=(group.longitude*count+p.node.longitude)/(count+1)
            group.members.push(p.node)
        }
    })
    // Reserve marker circles first, then admit only non-overlapping label rectangles.
    const boxes = groups.map(g => ({left:g.x-22,right:g.x+22,top:g.y-22,bottom:g.y+22}))
    if (zoom >= 10) {
        for (const g of groups) {
            if (g.members.length !== 1) continue
            const box = {left:g.x-110,right:g.x+110,top:g.y+27,bottom:g.y+53}
            if (!boxes.some(b => box.left < b.right && box.right > b.left && box.top < b.bottom && box.bottom > b.top)) {
                g.label=true; boxes.push(box)
            }
        }
    }
    return groups
}
