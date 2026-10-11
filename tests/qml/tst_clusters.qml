import QtQuick
import QtTest
import "../../MapClusters.js" as Clusters
TestCase {
    name: "MapClusters"
    function point(id,x,y) { return {x:x,y:y,node:{id:id,name:id,latitude:47,longitude:-122}} }
    function test_group_and_separate_with_zoom() {
        const close = [point("a",100,100),point("b",120,100),point("c",400,100)]
        let result=Clusters.build(close,8)
        compare(result.length,2)
        compare(result[0].members.length,2)
        compare(result[0].label,false)
        compare(Clusters.build([point("a",100,100),point("b",300,100),point("c",500,100)],14).length,3)
    }
    function test_labels_avoid_each_other() {
        const result=Clusters.build([point("a",100,100),point("b",170,100)],12)
        compare(result.length,2)
        compare(result.filter(g=>g.label).length,1)
    }
    function test_colocated_stay_accessible() {
        const result=Clusters.build([point("a",100,100),point("b",100,100)],19)
        compare(result.length,1)
        compare(result[0].members.length,2)
    }
}
