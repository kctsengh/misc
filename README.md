
package main
 
import (
    "context"
    "flag"
    "fmt"
    "io/ioutil"
    "net/http"
    "time"
    "cegppatcher.tsmc.com/hostsubnet"
     v2 "github.com/cilium/cilium/pkg/k8s/apis/cilium.io/v2"
    ciliumv2 "github.com/cilium/cilium/pkg/k8s/client/clientset/versioned/typed/cilium.io/v2"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/dynamic"
        klog "k8s.io/klog/v2"
 
    admission "k8s.io/api/admission/v1"
    v1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "encoding/json"
 
    "k8s.io/apimachinery/pkg/runtime/serializer"
    "k8s.io/client-go/rest"
)
var (
    runtimeScheme = runtime.NewScheme()
    codecFactory  = serializer.NewCodecFactory(runtimeScheme)
    deserializer  = codecFactory.UniversalDeserializer()
)
func init() {
    _ = corev1.AddToScheme(runtimeScheme)
    _ = admission.AddToScheme(runtimeScheme)
    _ = v1.AddToScheme(runtimeScheme)
}
type admitv1Func func(admission.AdmissionReview) *admission.AdmissionResponse
 
type admitHandler struct {
    v1 admitv1Func
}
type CegpGwNodePatcher struct {
    dynamicClient *dynamic.DynamicClient
    ciliumClient  *ciliumv2.CiliumV2Client
}
