% Copyright (c) 2017 The Chinese University of Hong Kong
% Written by Xiaowei Hu [xwhu@cse.cuhk.edu.hk]
% Thanks for Zhaowei Cai [zwcai-at-ucsd.edu] see mscnn/LICENSE for details
% Copyright (c) 2016 The Regents of the University of California

clear all; close all;

addpath('../../matlab/');
addpath('../../utils/'); 
  
%root_dir = 'SINet-pva-576-3-branches/'; 
root_dir = 'SINet-vgg-576-3-branches/'; 

%binary_file = [root_dir 'SINet_kitti_train_2nd_iter_75000.caffemodel'];
binary_file = [root_dir 'SINet_kitti_train_2nd_iter_initial.caffemodel'];

assert(exist(binary_file, 'file') ~= 0);
definition_file = [root_dir 'SINet_deploy.prototxt'];
assert(exist(definition_file, 'file') ~= 0);
use_gpu = true;
if (~use_gpu)
  caffe.set_mode_cpu();
else
  caffe.set_mode_gpu();  
  gpu_id = 0; caffe.set_device(gpu_id); 
end
% Initialize a network
net = caffe.Net(definition_file, binary_file, 'test');                                                

% set KITTI dataset directory
root_dir = '/home/xwhu/KITTI/KITTI/data_object_image_2/';
%image_dir = [root_dir 'testing/image_2/']; %test
image_dir = [root_dir 'training/image_2/'];
comp_id='SINet_KITTI_result'; 
%comp_id = 'kitti_8s_768_35k_test';

%image_list=textread('../../data/kitti/ImageSets/test.txt', '%s'); %test
%image_list=textread('../../data/kitti/ImageSets/train.txt', '%s');
image_list=textread('../../data/kitti/ImageSets/val.txt', '%s');
%image_list = dir([image_dir '*.png']); 
nImg=length(image_list);

% choose the right input size
  imgW = 1920; imgH = 576;
 
% imgW = 2560; imgH = 768;
% imgW = 1280; imgH = 384;
% imgW = 864; imgH = 256;

mu = ones(1,1,3); mu(:,:,1:3) = [104 117 123];
mu = repmat(mu,[imgH,imgW,1]);

% bbox de-normalization parameters
bbox_means = [0 0 0 0];
bbox_stds = [0.1 0.1 0.2 0.2];

% non-maxisum suppression parameters
pNms.type = 'maxg'; pNms.overlap = 0.5; pNms.ovrDnm = 'union';

% non-maxisum suppression + avgerage parameters
pAvg.type = 'maxg'; pAvg.overlap = 0.5;
pAvg.ovrDnm = 'union'; pAvg.merge_overlap = 0.8;

cls_ids = [2]; num_cls=length(cls_ids); 
obj_names = {'bg','car','van','truck','tram'};
final_detect_boxes = cell(nImg,num_cls); final_proposals = cell(nImg,1);
proposal_thr = -10; usedtime=0; 

%show if show=1 
show = 0; show_thr = 0.1;
if (show)
  fig=figure(1); set(fig,'Position',[-50 100 1350 375]);
  h.axes = axes('position',[0,0,1,1]);
end

for k = 1 : nImg
  test_image = imread([image_dir image_list{k} '.png']);
  if (show)
    imshow(test_image,'parent',h.axes); axis(h.axes,'image','off'); hold(h.axes,'on');
    %imwrite(test_image, ['results/'  image_list(k).name]);
  end
  [orgH,orgW,~] = size(test_image);
  ratios = [imgH imgW]./[orgH orgW];
  test_image = imresize(test_image,[imgH imgW]); 
  test_image = single(test_image(:,:,[3 2 1]));
  test_image = bsxfun(@minus,test_image,mu);
  test_image = permute(test_image, [2 1 3]);

  % network forward
  tic; outputs = net.forward({test_image});
  pertime=toc;
  usedtime=usedtime+pertime; avgtime=usedtime/k;
  
  tmp_bb1=squeeze(outputs{1});
  tmp_bb2=squeeze(outputs{2});
  tmp_bb3=squeeze(outputs{3});
  tmp_cls1=squeeze(outputs{4});
  tmp_cls2=squeeze(outputs{5});
  tmp_cls3=squeeze(outputs{6});
  
  hash_table = net.blobs('hash_table').get_data();
  roi_num = size(hash_table,4);
  
  bbox_preds = zeros(roi_num,20);
  cls_pred = zeros(roi_num,5);
  
  for i=1:roi_num
      if (hash_table(1,1,2,i)==1) %small
          bbox_preds(i,:) = tmp_bb3(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
          cls_pred(i,:) = tmp_cls3(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
      else if (hash_table(1,1,2,i)==2) %middle
              bbox_preds(i,:) = tmp_bb2(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
              cls_pred(i,:) = tmp_cls2(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
          else %large
              bbox_preds(i,:) = tmp_bb1(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
              cls_pred(i,:) = tmp_cls1(:,hash_table(1,1,1,i)+1)'; %hash_table(1,1,1,i) count from 0
          end
      end
  end
  
  
  tmp=squeeze(outputs{7}); tmp = tmp'; tmp = tmp(:,2:end); 
  tmp(:,3) = tmp(:,3)-tmp(:,1); tmp(:,4) = tmp(:,4)-tmp(:,2); 
  proposal_pred = tmp; proposal_score = proposal_pred(:,end);
  
  % filtering some bad proposals
  keep_id = find(proposal_score>=proposal_thr & proposal_pred(:,3)~=0 & proposal_pred(:,4)~=0);
  proposal_pred = proposal_pred(keep_id,:); 
  bbox_preds = bbox_preds(keep_id,:); cls_pred = cls_pred(keep_id,:);
    
  proposals = double(proposal_pred);
  proposals(:,1) = proposals(:,1)./ratios(2); 
  proposals(:,3) = proposals(:,3)./ratios(2);
  proposals(:,2) = proposals(:,2)./ratios(1);
  proposals(:,4) = proposals(:,4)./ratios(1);
  final_proposals{k} = proposals;

  for i = 1 : num_cls
    id = cls_ids(i); bbset = [];   %for car id=2
    bbox_pred = bbox_preds(:,id*4-3:id*4);  %5 8

    % bbox de-normalization
    bbox_pred = bbox_pred.*repmat(bbox_stds,[size(bbox_pred,1) 1]);  %bbox_stds(size(bbox_pred,1), 1)
    bbox_pred = bbox_pred+repmat(bbox_means,[size(bbox_pred,1) 1]);  %bbox_means(size(bbox_pred,1), 1)

    exp_score = exp(cls_pred);
    sum_exp_score = sum(exp_score,2);
    prob = exp_score(:,id)./sum_exp_score; 
    ctr_x = proposal_pred(:,1)+0.5*proposal_pred(:,3); %central
    ctr_y = proposal_pred(:,2)+0.5*proposal_pred(:,4);
    tx = bbox_pred(:,1).*proposal_pred(:,3)+ctr_x; %regression
    ty = bbox_pred(:,2).*proposal_pred(:,4)+ctr_y;
    tw = proposal_pred(:,3).*exp(bbox_pred(:,3));
    th = proposal_pred(:,4).*exp(bbox_pred(:,4));
    tx = tx-tw/2; ty = ty-th/2;
    tx = tx./ratios(2); tw = tw./ratios(2);
    ty = ty./ratios(1); th = th./ratios(1);

    % clipping bbs to image boarders
    tx = max(0,tx); ty = max(0,ty);
    tw = min(tw,orgW-tx); th = min(th,orgH-ty);     
    bbset = double([tx ty tw th prob]);
    idlist = 1:size(bbset,1); bbset = [bbset idlist'];
    
    if (isempty(bbset))
        continue;
    end
    
    
    %%%%%%%test for NMS
    bb_all{k} = bbset;
    
    %bbset=bbNms(bbset,pNms);
    bbset=bbAvgNms(bbset,pAvg);
    final_detect_boxes{k,i} = bbset(:,1:5);

    if (show) 
      proposals_show = zeros(0,5); bbs_show = zeros(0,6);
      if (size(bbset,1)>0) 
        show_id = find(bbset(:,5)>=show_thr);
        bbs_show = bbset(show_id,:);
        proposals_show = proposals(bbs_show(:,6),:); 
      end
      % proposal
%       for j = 1:size(proposals_show,1)
%         rectangle('Position',proposals_show(j,1:4),'EdgeColor','g','LineWidth',2);
%         show_text = sprintf('%.2f',proposals_show(j,5));
%         x = proposals_show(j,1)+0.5*proposals_show(j,3);
%         text(x,proposals_show(j,2),show_text,'color','r', 'BackgroundColor','k','HorizontalAlignment',...
%             'center', 'VerticalAlignment','bottom','FontWeight','bold', 'FontSize',8);
%       end 
      % detection
      for j = 1:size(bbs_show,1)
        rectangle('Position',bbs_show(j,1:4),'EdgeColor','y','LineWidth',2);
        show_text = sprintf('%s=%.2f',obj_names{id},bbs_show(j,5));
        x = bbs_show(j,1)+0.5*bbs_show(j,3);
        text(x,bbs_show(j,2),show_text,'color','r', 'BackgroundColor','k','HorizontalAlignment',...
            'center', 'VerticalAlignment','bottom','FontWeight','bold', 'FontSize',8);
      end 
      
      %% if uncomment the following three lines, the results can be saved in 'results/'
      handle=gca;%gcf
      saveas(handle,['results/'  image_list{k,1} '.jpg']);
      clear handle;
    end
  end
  
  if (mod(k,100)==0), fprintf('idx %i/%i, avgtime=%.4fs\n',k,nImg,avgtime); end
end

for i=1:nImg
  for j=1:num_cls
    final_detect_boxes{i,j}=[ones(size(final_detect_boxes{i,j},1),1)*i final_detect_boxes{i,j}]; 
  end
  final_proposals{i}=[ones(size(final_proposals{i},1),1)*i final_proposals{i}];
end

for i=1:size(final_detect_boxes,1)
    if (isempty(final_detect_boxes{i}))
        final_detect_boxes{i} = [i,0,0,0,0,0];
    end 
end


for j=1:num_cls
  id = cls_ids(j);  
  save_detect_boxes=cell2mat(final_detect_boxes(:,j));
  dlmwrite(['detections/' comp_id '_' obj_names{id} '.txt'],save_detect_boxes);
end
final_proposals=cell2mat(final_proposals);
dlmwrite(['proposals/' comp_id '.txt'],final_proposals);

caffe.reset_all();

save bb_all bb_all

cd ../kitti_result;
writeDetForEval;
cd ../kitti_car;
