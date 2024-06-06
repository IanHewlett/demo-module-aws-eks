require 'json'
env = ENV['ENVIRONMENT']

RSpec.describe 'Vault K8S Auth'
describe "admin namespace cluster #{env}" do

  # describe 'admin policy' do
  #   let(:policy_config_hcl) { `vault policy read -namespace=admin di-admin-kubernetes-policy` }
  #   subject { HCL::Checker.parse(policy_config_hcl) }
  #   it do
  #     expect(subject['path']).to include(
  #                                  { 'secret/*' => { 'capabilities' => %w[read] } },
  #                                  { 'database/*' => { 'capabilities' => %w[read] } },
  #                                  { 'shared/*' => { 'capabilities' => %w[read create update delete list patch sudo] } },
  #                                  )
  #   end
  # end

  describe 'auth method is enabled' do
    let(:auth_methods) { JSON.parse(`vault auth list -namespace=admin -format=json`) }

    it { expect(auth_methods).to include("#{env}/") }
  end

  describe 'admin role' do
    let(:admin_role) do
      JSON.parse(`vault read -namespace=admin -format json auth/#{env}/role/di-admin-kubernetes-role`)
    end
    it do
      bound_namespaces = ["istio-system", "cert-manager", "kube-system", "connaisseur"]
      expect(admin_role).to include(
        'data' => include(
          'token_policies' => eq(["di-admin-kubernetes-policy"]),
          'bound_service_account_namespaces' => match_array(bound_namespaces)
        )
      )
    end
  end
end
