'use strict';
const fs=require('fs');const path=require('path');
const {DefaultArtifactClient}=require(path.join(process.env.GITHUB_WORKSPACE,'node_modules','@actions','artifact'));
(async()=>{
 const root=path.join(process.env.GITHUB_WORKSPACE,'delivery');
 const release=JSON.parse(fs.readFileSync(path.join(root,'RELEASE.json'),'utf8'));
 const client=new DefaultArtifactClient();const artifacts=[];
 const group=process.env.PART_GROUP?Number(process.env.PART_GROUP):0;
 const parts=release.parts.slice(group*8,group*8+8);
 if(!parts.length)throw new Error('No payload parts selected');
 for(const part of parts){
  const p=path.join(root,part.name);
  if(!fs.existsSync(p)||fs.statSync(p).size>=100*1024*1024)throw new Error('Invalid or oversized part');
  const name='cc17-release-'+part.name.replaceAll('.','-');
  const r=await client.uploadArtifact(name,[p,path.join(root,'RELEASE.json')],root,{compressionLevel:0,retentionDays:30});
  artifacts.push({name,id:r.id,size:r.size,digest:r.digest,part:part.name,part_sha256:part.sha256});
 }
 const index={label:release.label,group,artifacts,release};
 fs.writeFileSync(path.join(root,'ARTIFACT_INDEX.json'),JSON.stringify(index,null,2));
 const r=await client.uploadArtifact('cc17-release-index-'+release.label+'-'+group,[path.join(root,'ARTIFACT_INDEX.json')],root,{compressionLevel:0,retentionDays:30});
 console.log('CC17_ARTIFACT_INDEX '+JSON.stringify({...index,index_artifact_id:r.id}));
})().catch(e=>{console.error(e.message);process.exit(1)});
