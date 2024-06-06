require 'json'

instance = input('instance')
aws_region = input('aws_region')
cluster_eks_version = input('cluster_eks_version')
management_node_group_instance_types = input('management_node_group_instance_types')
vpc_cni_version = input('vpc_cni_version')
coredns_version = input('coredns_version')
kube_proxy_version = input('kube_proxy_version')
aws_ebs_csi_driver_version = input('aws_ebs_csi_driver_version')
management_node_group_name = input('management_node_group_name')
management_node_group_min_size = input('management_node_group_min_size')


client = Aws::EC2::Resource.new(region: "#{aws_region}")
ec2_instances = client.instances({
 filters: [
   {
     name: "tag:eks:cluster-name",
     values: ["#{instance}"]
   },
   {
     name: "instance-state-name",
     values: ['running']
   }
 ]
})

control "cluster" do
  title "Check that cluster exists, is running, and has the expected version."
  tag "spec"

  describe aws_eks_cluster(instance) do
    it { should exist }
    its('status') { should eq 'ACTIVE' }
    its('version') { should eq "#{cluster_eks_version}" }
  end
end

control "nodes" do
  title "Check that existing node groups match one of the expected instance types."
  tag "spec"

  ec2_instances.each do |instance|
    describe "#{management_node_group_instance_types}" do
      it { should include instance.instance_type }
    end
  end
end

control "asg metrics" do
  title "Check that metric collection is enabled for AutoScalingGroups."
  tag "spec"

  describe "Autoscaling group metric collection" do
    let(:autoscaling_group) { JSON.parse(`aws autoscaling describe-auto-scaling-groups --filter Name=tag:eks:cluster-name,Values=#{instance}`) }

    it 'the metric collection should be enabled' do
      expect(autoscaling_group['AutoScalingGroups'][0]['EnabledMetrics']).not_to be(nil)
    end
  end
end

control "eks addons" do
  title "Check that eks addons match target specified versions."
  tag "spec"

  describe 'aws add-ons version' do
    let(:vpc_cni_version) { JSON.parse(`aws eks describe-addon --addon-name vpc-cni  --cluster-name #{instance}`) ['addon']['addonVersion'] }
    it 'should update to the correct vpc_cni version' do
      expect(vpc_cni_version).to eq("#{vpc_cni_version}")
    end

    let(:coredns_version) { JSON.parse(`aws eks describe-addon --addon-name coredns --cluster-name #{instance}`) ['addon']['addonVersion'] }
    it 'should update to the correct coredns_version version' do
      expect(coredns_version).to eq("#{coredns_version}")
    end

    let(:kube_proxy_version) { JSON.parse(`aws eks describe-addon --addon-name kube-proxy  --cluster-name #{instance}`) ['addon']['addonVersion'] }
    it 'should update to the correct kube_proxy version' do
      expect(kube_proxy_version).to eq("#{kube_proxy_version}")
    end

    let(:ebs_csi_driver_version) { JSON.parse(`aws eks describe-addon --addon-name aws-ebs-csi-driver --cluster-name #{instance}`) ['addon']['addonVersion'] }
    it 'should update to the correct ebs_csi_driver version' do
      expect(ebs_csi_driver_version).to eq("#{aws_ebs_csi_driver_version}")
    end
  end
end

control "node k8s status" do
  title "Check that nodes are up and running."
  tag "spec"

  describe 'management node group' do

    describe 'node presence' do
      let(:node_config) {JSON.parse(`kubectl get nodes -l nodegroup=#{management_node_group_name} -o json`)}
      it 'nodes should be present' do
        expect(node_config.count).to be >=(Integer(management_node_group_min_size))
      end
    end

    describe 'node status' do
      let(:node_config) {JSON.parse(`kubectl get nodes -l nodegroup=#{management_node_group_name} -o json | jq -r '.items[] | select(.status.conditions[].type=="Ready")' | jq -s '.' `)}
      it 'nodes should be ready' do
        expect(node_config.count).to be >=(Integer(management_node_group_min_size))
      end
    end
  end

end

control "eks addon k8s status" do
  title "Check that eks addons exist within the cluster and match specifications."
  tag "spec"

  describe 'aws add-ons status' do
    let(:vpc_cni_config) {JSON.parse(`kubectl get ds aws-node -n kube-system -o json`)}
    it 'vpc_cni should be running' do
      expect(vpc_cni_config.dig('status', 'currentNumberScheduled')).to eq(vpc_cni_config.dig('status', 'desiredNumberScheduled'))
    end
    let(:kube_proxy_config) {JSON.parse(`kubectl get ds kube-proxy -n kube-system -o json`)}
    it 'kube_proxy should be running' do
      expect(kube_proxy_config.dig('status', 'currentNumberScheduled')).to eq(kube_proxy_config.dig('status', 'desiredNumberScheduled'))
    end

    describe 'coredns' do
      let(:coredns_config) {JSON.parse(`kubectl get deploy coredns -n kube-system -o json`)}
      it 'coredns should be running' do
        expect(coredns_config.dig('status', 'readyReplicas')).to eq(coredns_config.dig('status', 'replicas'))
      end

      pods = JSON.parse(`kubectl get pods -l k8s-app=kube-dns -n kube-system -o json`)
      pods.dig('items').each do |pod|
        node = JSON.parse(`kubectl get nodes #{pod.dig('spec', 'nodeName')} -o json`)
        it "runs on management nodes" do
          expect(node.dig('metadata', 'labels', 'nodegroup')).to include("management")
        end
      end
    end

    describe 'aws_ebs_csi_driver' do
      let(:aws_ebs_csi_driver_config) {JSON.parse(`kubectl get deploy ebs-csi-controller -n kube-system -o json`)}
      it 'aws_ebs_csi_driver should be running' do
        expect(aws_ebs_csi_driver_config.dig('status', 'readyReplicas')).to eq(aws_ebs_csi_driver_config.dig('status', 'replicas'))
      end

      pods = JSON.parse(`kubectl get pods -l app=ebs-csi-controller -n kube-system -o json`)
      pods.dig('items').each do |pod|
        node = JSON.parse(`kubectl get nodes #{pod.dig('spec', 'nodeName')} -o json`)
        it "runs on management nodes" do
          expect(node.dig('metadata', 'labels', 'nodegroup')).to include("management")
        end
      end
    end
  end
end

# control "roles" do
#   describe aws_iam_role(role_name: tfvars['instance_name'] + '-common-node-role') do
#     it { should exist }
#   end
# end

# control "aws-auth" do
#   describe "common" do
#     it 'exists within aws-auth' do
#       aws_auth_config = YAML.load(`kubectl get configmap aws-auth -o yaml -n kube-system`)
#       karpenter_role = YAML.load(aws_auth_config.dig('data', 'mapRoles')).find { |x| x['rolearn'].include? "#{tfvars['instance_name']}-common-node-role" }
#       expect(karpenter_role.keys).to eq(['groups', 'rolearn', 'username'])
#       expect(karpenter_role['groups']).to eq(["system:bootstrappers", "system:nodes"])
#       expect(karpenter_role['username']).to eq("system:node:{{EC2PrivateDNSName}}")
#     end
#   end
# end
