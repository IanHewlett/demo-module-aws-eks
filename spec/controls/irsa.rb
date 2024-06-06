require 'json'

control "irsa" do
  title "Check irsa"
  tag "spec"

  instance = input('instance')

  describe aws_iam_role(role_name: "#{instance}-aws-load-balancer-controller") do
    it { should exist }
  end

  describe aws_iam_role(role_name: "#{instance}-cert-manager") do
    it { should exist }
  end

  describe aws_iam_role(role_name: "#{instance}-efs-csi-controller-sa") do
    it { should exist }
  end

  describe aws_iam_role(role_name: "#{instance}-external-dns") do
    it { should exist }
  end

  describe aws_iam_role(role_name: "#{instance}-karpenter-controller") do
    it { should exist }
  end
end
