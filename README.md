package hostsubnet
 
import (
    "context"
    "encoding/json"
    "fmt"
    "sync"
    "time"
 
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
        "k8s.io/apimachinery/pkg/types"
    "k8s.io/client-go/dynamic"
    "k8s.io/klog"
)
 
func Abc() string {
    return "abc"
}
func GetHostsubnet(dclient dynamic.Interface) (*HostsubnetList, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
 
    raw_list, err := dclient.Resource(gvr).List(ctx, metav1.ListOptions{})
    if err != nil { 
            klog.Warningf("Error occur: getHostSubnet (%s)", err.Error())
        return nil, err
    }
 
    data, err := raw_list.MarshalJSON()
        if err != nil {
        klog.Warningf("Error occur: hostsubnet to Json (%s)", err.Error())
        return nil, err
    }
     var hsList HostsubnetList
    if err := json.Unmarshal(data, &hsList); err != nil {
        klog.Warningf("Error occur: Json to hostsubnet (%s)", err.Error())
        return nil, err
    }
     return &hsList, nil
}   
