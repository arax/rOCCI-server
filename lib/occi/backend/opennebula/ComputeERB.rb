##############################################################################
#  Copyright 2011 Service Computing group, TU Dortmund
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
##############################################################################

##############################################################################
# Description: OpenNebula Backend
# Author(s): Hayati Bice, Florian Feldhaus, Piotr Kasprzak
##############################################################################

module OCCI
  module Backend
    module OpenNebula
      module Compute

        # ---------------------------------------------------------------------------------------------------------------------     
        class ComputeERB
          
          @compute          = nil
          @networks         = []
          @storage          = []
          @external_storage = []
          @nfs_mounts       = [] 
          
          attr_accessor :compute
          attr_accessor :networks
          attr_accessor :storage
          attr_accessor :nfs_mounts
          attr_accessor :external_storage 
                  
          # Support templating of member data.
          def get_binding
            binding
          end
        end

      end
    end
  end
end