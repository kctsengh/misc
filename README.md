
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

func (m *CegpGwNodePatcher) serveMutate(w http.ResponseWriter, r *http.Request) {
    serve(w, r, AdmitHandler(m.mutate))
}

func AdmitHandler(f admitv1Func) admitHandler {
    return admitHandler{
        v1: f,
    }
}
func serve(w http.ResponseWriter, r *http.Request, admit admitHandler) {
    var body []byte
    if r.Body != nil {
        if data, err := ioutil.ReadAll(r.Body); err == nil {
            body = data
        }
    }
        contentType := r.Header.Get("Content-Type")
    if contentType != "application/json" {
        klog.Errorf("contentType=%s, expect application/json", contentType)
        return
    }
    klog.Infof("handling request: %s", body)
    var responseObj runtime.Object
    if obj, gvk, err := deserializer.Decode(body, nil, nil); err != nil {
        msg := fmt.Sprintf("Request could not be decoded: %v", err)
        klog.Error(msg)
         http.Error(w, msg, http.StatusBadRequest)
        return
 
    } else {
        requestedAdmissionReview, ok := obj.(*admission.AdmissionReview)
        if !ok {
            klog.Errorf("Expected v1.AdmissionReview but got: %T", obj)
            return
        }
        responseAdmissionReview := &admission.AdmissionReview{}
        responseAdmissionReview.SetGroupVersionKind(*gvk)
                responseAdmissionReview.Response = admit.v1(*requestedAdmissionReview)
        responseAdmissionReview.Response.UID = requestedAdmissionReview.Request.UID
        responseObj = responseAdmissionReview
 
    }

        klog.Infof("sending response: %v", responseObj)
    respBytes, err := json.Marshal(responseObj)
    if err != nil {
        klog.Error(err)
        http.Error(w, err.Error(), http.StatusInternalServerError)
                return
    }
    w.Header().Set("Content-Type", "application/json")
    if _, err := w.Write(respBytes); err != nil {
        klog.Error(err)
     }
}
 
type patchOperation struct {
    Op    string      `json:"op"`
    Path  string      `json:"path"`
    Value interface{} `json:"value,omitempty"`
}
func (m *CegpGwNodePatcher) mutate(ar admission.AdmissionReview) *admission.AdmissionResponse {
    klog.Info("mutating cegp")
 
    raw := ar.Request.Object.Raw
        cegp := v2.CiliumEgressGatewayPolicy{}
    if _, _, err := deserializer.Decode(raw, nil, &cegp); err != nil {
        klog.Error(err)
        return &admission.AdmissionResponse{
                    Result: &metav1.Status{
                Message: err.Error(),
            },
        }
    }
 
    hs, err := hostsubnet.GetHostsubnet(m.dynamicClient)
    if err != nil {
        klog.Error(err)
        return &admission.AdmissionResponse{
            Result: &metav1.Status{
                Message: err.Error(),
            },
        }
    }
        klog.Infof("hs result: %+v\n", hs.Items)
 
    eIP := cegp.Spec.EgressGateway.EgressIP
    var hsExist bool
    for _, h := range hs.Items {
        for _, hIP := range h.Spec.EgressIPs {
                    if hIP == eIP {
                cegp.Spec.EgressGateway.NodeSelector.MatchLabels["name"] = h.Spec.Hostname
                hsExist = true
            }
        }
    }
        if !hsExist {
        return &admission.AdmissionResponse{
            Result: &metav1.Status{
                Message: "no node binds egress IP: " + eIP,
            },
        }
    }
    pt := admission.PatchTypeJSONPatch
    pto := []patchOperation{
        {
            Op:    "add",
            Path:  "/spec/egressGateway",
            Value: cegp.Spec.EgressGateway,
           },
    }
 
    ptj, err := json.Marshal(pto)
    if err != nil {
 
        fmt.Println(err)
        return &admission.AdmissionResponse{
                    Result: &metav1.Status{
                Message: err.Error(),
            },
        }
    }
 
    return &admission.AdmissionResponse{Allowed: true, PatchType: &pt, Patch: ptj}
}
func (m *CegpGwNodePatcher) Patch() {
    cegpCtx := context.Background()
    cegps, err := m.ciliumClient.CiliumEgressGatewayPolicies().List(cegpCtx, metav1.ListOptions{})
        if err != nil {
        klog.Error(err)
        return
    }
    klog.Infof("cegp result: %+v\n", cegps.Items)
        hs, err := hostsubnet.GetHostsubnet(m.dynamicClient)
    if err != nil {
        klog.Error(err)
        return
    }

        klog.Infof("hs result: %+v\n", hs.Items)
 
    for _, h := range hs.Items {
        node := h.Spec.Hostname
        for _, hIP := range h.Spec.EgressIPs {
                    for _, c := range cegps.Items {
                if c.Spec.EgressGateway.EgressIP == hIP {
                    var needUpdate bool
 
                    if val, ok := c.Spec.EgressGateway.NodeSelector.MatchLabels["name"]; ok {
                                           if val != node {
                            c.Spec.EgressGateway.NodeSelector.MatchLabels["name"] = node
                            needUpdate = true
                        }
                    }else {
                        c.Spec.EgressGateway.NodeSelector.MatchLabels["name"] = node
                        needUpdate = true
                    }
                    if needUpdate {
                         //cliCtx := context.Background()
                        //m.ciliumClient.CiliumEgressGatewayPolicies().Update(cliCtx, &c, metav1.UpdateOptions{})
                        klog.Infof("cegp updated: %+v\n", c)
                                            }
                }
            }
        }
    }
}
func main() {
    klog.Info("------- started -------")
    var tlsKey, tlsCert string
    flag.StringVar(&tlsKey, "tlsKey", "/etc/certs/tls.key", "Path to the TLS key")
        flag.StringVar(&tlsCert, "tlsCert", "/etc/certs/tls.crt", "Path to the TLS certificate")
    flag.Parse()
 
    // creates the in-cluster config
    config, err := rest.InClusterConfig()
    if err != nil {
        panic(err.Error())
    }
        ctx := context.Background()
    ticker := time.NewTicker(15 * time.Second)
    defer ticker.Stop()
 
    cli, err := ciliumv2.NewForConfig(config)
        if err != nil {
        panic(err.Error())
    }
 
    dclient, err := dynamic.NewForConfig(config)
    if err != nil {
        go func() {
        for {
            select {
            case <-ticker.C:
                ptcr.Patch()
            case <-ctx.Done():
                return
            }
        }
 
    }()
        http.HandleFunc("/mutate", ptcr.serveMutate)
 
    err = http.ListenAndServeTLS(":8443", tlsCert, tlsKey, nil)
    if err != nil {
        klog.Fatal(err)
            }
 
}
